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

    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    @ObservationIgnored private var livenessTask: Task<Void, Never>?
    @ObservationIgnored private let probe: ProcessLivenessProbing
    @ObservationIgnored private let livenessInterval: TimeInterval

    init(probe: ProcessLivenessProbing = SystemProcessProbe(), livenessInterval: TimeInterval = 5) {
        self.probe = probe
        self.livenessInterval = livenessInterval
    }

    /// Canlılık döngüsü çalışıyor mu (testler yaşam döngüsünü buradan doğrular).
    var isPollingLiveness: Bool { livenessTask != nil }

    func ingest(_ event: AgentEvent, now: Date = .now) {
        lastEventAt = now
        var next = state
        guard next.apply(event, now: now) else { return }
        state = next
        refreshSummary()
        schedulePrune()
        updateLivenessPolling()
    }

    func prune(now: Date = .now) {
        var next = state
        guard !next.prune(now: now).isEmpty else { return }
        state = next
        refreshSummary()
        updateLivenessPolling()
    }

    /// Pid'li oturumların süreçlerini bir kez yoklar; ölü bulunanlar kapanır (kısa süre sonra düşer). Zamanlayıcı bunu çağırır.
    func pollLiveness(now: Date = .now) {
        var next = state
        if !next.applyLiveness(using: probe, now: now).isEmpty { state = next; refreshSummary() }
        else if next != state { state = next } // yalnızca süreç başlangıcı kaydedildi
        schedulePrune()
        updateLivenessPolling()
    }

    /// "Hedefi de göster" kapanınca mevcut hedefleri atar (yeni olay beklemeden balonlar güncellenir).
    func clearTargets() {
        var next = state
        next.clearTargets()
        if next != state { state = next }
    }

    /// Dinleyici kapanınca listeyi boşalt.
    func reset() {
        pruneTask?.cancel()
        pruneTask = nil
        livenessTask?.cancel()
        livenessTask = nil
        state = AgentState()
        lastEventAt = nil
        refreshSummary()
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
