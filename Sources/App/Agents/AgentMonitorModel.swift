import Foundation
import Observation

/// Menü çubuğu öğesinin izlediği küçük özet: yalnızca değişince atanır (olay başına yeniden çizim yok).
struct AgentSummary: Equatable, Sendable {
    var working = 0
    var sessions = 0
}

/// Canlı Claude oturum ağacı. Olay gelince saf `AgentState` güncellenir; zamanlayıcı yalnızca oturum varken, bir sonraki
/// bayatlama anına kurulan tek seferlik bir uykudur (boşta sıfır CPU). Panel görünmüyorken hiçbir görünüm bunu okumaz.
/// Canlılık: yalnızca kapanmamış, pid'i bilinen oturum varken tek bir tolerance'lı döngü (5 sn) süreçleri yoklar; hedef kalmayınca
/// (ya da `reset`) durur.
@MainActor @Observable
final class AgentMonitorModel {
    private(set) var state = AgentState()
    private(set) var lastEventAt: Date?
    /// Menü çubuğu öğesi yalnızca bunu gözler.
    private(set) var summary = AgentSummary()

    /// Durum her değiştiğinde (olay, budama, canlılık, sıfırlama) çağrılır; tarayıcı görünümü bunu SSE'ye çevirir. Zamanlayıcı yok.
    @ObservationIgnored var onStateChange: (@MainActor (AgentState) -> Void)?
    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    @ObservationIgnored private var livenessTask: Task<Void, Never>?
    @ObservationIgnored private let probe: ProcessLivenessProbing
    @ObservationIgnored private let livenessInterval: TimeInterval
    /// Modeli bilinmeyen oturumlar için konuşma dosyası araması; nil = kapalı (testlerde gerçek dosyaya dokunulmaz).
    @ObservationIgnored private let modelResolver: (any SessionModelResolving)?
    @ObservationIgnored private var lookups = ModelLookupTracker()

    init(probe: ProcessLivenessProbing = SystemProcessProbe(), livenessInterval: TimeInterval = 5,
         modelResolver: (any SessionModelResolving)? = nil) {
        self.probe = probe
        self.livenessInterval = livenessInterval
        self.modelResolver = modelResolver
    }

    /// Canlılık döngüsü çalışıyor mu (testler yaşam döngüsünü buradan doğrular).
    var isPollingLiveness: Bool { livenessTask != nil }

    func ingest(_ event: AgentEvent, now: Date = .now) {
        lastEventAt = now
        var next = state
        guard next.apply(event, now: now) else { return }
        commit(next)
        refreshSummary()
        schedulePrune()
        updateLivenessPolling()
        lookUpUnknownModels(now: now)
    }

    /// Modeli bilinmeyen oturum için, hız sınırı izin veriyorsa arka plan kuyruğunda konuşma dosyasının yalnızca model alanını okur.
    /// Yalnızca olay gelince tetiklenir (zamanlayıcı yok); model bilinince durur.
    private func lookUpUnknownModels(now: Date) {
        guard let resolver = modelResolver else { return }
        for id in state.sessionsWithUnknownModel.sorted() where lookups.shouldAttempt(id, now: now) {
            Task.detached(priority: .utility) { [weak self] in
                let model = resolver.latestModel(sessionID: id)
                await self?.finishLookup(id, model: model)
            }
        }
    }

    private func finishLookup(_ id: String, model: String?) {
        var next = state
        let adopted = model.map { next.adoptTranscriptModel($0, for: id) } ?? false
        lookups.finish(id, found: model != nil, now: .now)
        if adopted { commit(next) }
    }

    func prune(now: Date = .now) {
        var next = state
        guard !next.prune(now: now).isEmpty else { return }
        commit(next)
        lookups.retain(Set(state.sessions.keys))
        refreshSummary()
        updateLivenessPolling()
    }

    /// Pid'li oturumların süreçlerini bir kez yoklar; ölü bulunanlar kapanır (kısa süre sonra düşer). Zamanlayıcı bunu çağırır.
    func pollLiveness(now: Date = .now) {
        var next = state
        if !next.applyLiveness(using: probe, now: now).isEmpty { commit(next); refreshSummary() }
        else if next != state { commit(next) } // yalnızca süreç başlangıcı kaydedildi
        schedulePrune()
        updateLivenessPolling()
    }

    /// "Hedefi de göster" kapanınca mevcut hedefleri atar (yeni olay beklemeden balonlar güncellenir).
    func clearTargets() {
        var next = state
        next.clearTargets()
        if next != state { commit(next) }
    }

    /// Dinleyici kapanınca listeyi boşalt.
    func reset() {
        pruneTask?.cancel()
        pruneTask = nil
        livenessTask?.cancel()
        livenessTask = nil
        commit(AgentState())
        lookups.removeAll()
        lastEventAt = nil
        refreshSummary()
    }

    private func commit(_ next: AgentState) {
        state = next
        onStateChange?(next)
    }

    private func refreshSummary() {
        let next = AgentSummary(working: state.workingAgentCount, sessions: state.sessions.count)
        if next != summary { summary = next }
    }

    private func schedulePrune() {
        pruneTask?.cancel()
        guard let due = state.nextPruneDate() else { pruneTask = nil; return }
        let delay = max(1, due.timeIntervalSinceNow)
        pruneTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.prune()
            self.schedulePrune()
        }
    }

    private func updateLivenessPolling() {
        let hasTargets = !state.livenessTargets.isEmpty
        if !hasTargets {
            livenessTask?.cancel()
            livenessTask = nil
            return
        }
        guard livenessTask == nil else { return }
        let interval = livenessInterval
        livenessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval * 0.4))
                guard !Task.isCancelled, let self else { return }
                self.pollLiveness()
            }
        }
    }
}
