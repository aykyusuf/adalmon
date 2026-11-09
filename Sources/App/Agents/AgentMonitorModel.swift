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
    /// Elle küçültülen / elle açılan oturumlar (bellekte). Küçük oturumlar ofiste oda yerine sekme olarak durur.
    private(set) var dockOverrides: [String: SessionDockOverride] = [:]
    /// Otomatik küçülme anı gelince artar: görünümler `dock`'u yeniden hesaplasın diye (zamana bağlı karar için tek gözlenen alan).
    private(set) var dockRevision = 0
    @ObservationIgnored private var dormancyTask: Task<Void, Never>?
    @ObservationIgnored private var dormancyDue: Date?

    /// Durum her değiştiğinde (olay, budama, canlılık, sıfırlama) çağrılır; tarayıcı görünümü bunu SSE'ye çevirir. Zamanlayıcı yok.
    @ObservationIgnored var onStateChange: (@MainActor (AgentState) -> Void)?
    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    @ObservationIgnored private var livenessTask: Task<Void, Never>?
    @ObservationIgnored private let probe: ProcessLivenessProbing
    @ObservationIgnored private let livenessInterval: TimeInterval
    /// Modeli bilinmeyen oturumlar için konuşma dosyası araması; nil = kapalı (testlerde gerçek dosyaya dokunulmaz).
    @ObservationIgnored private let modelResolver: (any SessionModelResolving)?
    @ObservationIgnored private var lookups = ModelLookupTracker()
    /// Arka plan işlemleri örnekleyicisi (süreç ağacı). Yalnızca gözlemci varken ve pid'li açık oturum varken çalışır.
    @ObservationIgnored private let shellSampler: SessionProcessSampler
    @ObservationIgnored private let shellInterval: TimeInterval
    @ObservationIgnored private var shellTask: Task<Void, Never>?
    /// Arka plan işlemlerini gösteren açık arayüz sayısı (panel, ofis sayfası/pencere/duvar kâğıdı, web SSE istemcisi).
    private(set) var shellObservers = 0

    init(probe: ProcessLivenessProbing = SystemProcessProbe(), livenessInterval: TimeInterval = 5,
         modelResolver: (any SessionModelResolving)? = nil, shellSampler: SessionProcessSampler = SessionProcessSampler(),
         shellInterval: TimeInterval = 5) {
        self.probe = probe
        self.livenessInterval = livenessInterval
        self.modelResolver = modelResolver
        self.shellSampler = shellSampler
        self.shellInterval = shellInterval
    }

    /// Açık (oda) ve küçük (sekme) oturumlar. Durum, elle karar ya da `dockRevision` değişince yeniden hesaplanır.
    var dock: (open: [AgentSession], minimized: [AgentSession]) {
        _ = dockRevision
        return SessionDormancy.partition(state.orderedSessions, overrides: dockOverrides, now: .now)
    }

    /// Oturumu elle küçültür (çalışmaya başlayınca kendiliğinden açılır).
    func minimize(_ id: String) {
        guard state.sessions[id] != nil else { return }
        dockOverrides[id] = .minimized
        dockChanged()
    }

    /// Küçük oturumu açar; boşta sayacı bu andan yeniden başlar.
    func restore(_ id: String, now: Date = .now) {
        guard state.sessions[id] != nil else { return }
        dockOverrides[id] = .opened(at: now)
        dockChanged()
    }

    private func dockChanged() {
        dockRevision &+= 1
        scheduleDormancy()
        onStateChange?(state)
    }

    /// Düşen oturumların kararlarını ve çalışmaya başlamış oturumların "elle küçült" kararını temizler.
    private func tidyDockOverrides() {
        guard !dockOverrides.isEmpty else { return }
        for (id, o) in dockOverrides {
            guard let s = state.sessions[id] else { dockOverrides[id] = nil; continue }
            if o == .minimized, SessionDormancy.needsAttention(s) { dockOverrides[id] = nil }  // izin bekliyor: oda açılır ve açık kalır
        }
    }

    /// Bir sonraki otomatik küçülme anına tek seferlik uyku (boşta sıfır CPU). Aynı an için yeniden kurulmaz.
    private func scheduleDormancy() {
        let due = SessionDormancy.nextDormantDate(state.orderedSessions, overrides: dockOverrides, now: .now)
        guard due != dormancyDue else { return }
        dormancyTask?.cancel()
        dormancyDue = due
        guard let due else { dormancyTask = nil; return }
        let delay = max(1, due.timeIntervalSinceNow)
        dormancyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            self.dormancyDue = nil
            self.dockChanged()
        }
    }

    /// Arka plan işlemi örnekleme görevi çalışıyor mu (testler yaşam döngüsünü buradan doğrular).
    var isPollingShells: Bool { shellTask != nil }

    /// Bir arayüz görünür oldu (+1). Görünürken eşleştirilmiş `removeShellObserver` çağrılmalıdır.
    func addShellObserver() {
        shellObservers += 1
        updateShellPolling()
    }

    func removeShellObserver() {
        shellObservers = max(0, shellObservers - 1)
        updateShellPolling()
    }

    /// Gözlemci > 0 ve pid'li açık oturum varsa tek bir arka plan görevi; aksi halde hiçbir iş yok (zamanlayıcı yok).
    /// Durunca eski örnekler atılır (bayat veri gösterilmez).
    private func updateShellPolling() {
        if shellObservers > 0, !state.livenessTargets.isEmpty {
            guard shellTask == nil else { return }
            let interval = shellInterval
            shellTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.sampleShells()
                    try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval * 0.3))
                }
            }
        } else {
            shellTask?.cancel()
            shellTask = nil
            var next = state
            if next.setShells([:]) { commit(next) }
        }
    }

    /// Tek örnekleme: süreç tablosu `.utility` önceliğinde ana thread dışında okunur; sonuç değiştiyse yazılır.
    func sampleShells() async {
        let roots = state.livenessTargets
        guard !roots.isEmpty else { return }
        let sampler = shellSampler
        let pids = roots.map(\.pid)
        let bySession = await Task.detached(priority: .utility) { sampler.sample(roots: pids) }.value
        guard shellObservers > 0 else { return }
        var mapped: [String: SessionShells] = [:]
        for t in roots { mapped[t.sessionID] = bySession[t.pid] ?? .empty }
        var next = state
        if next.setShells(mapped) { commit(next) }
    }

    @ObservationIgnored private var lastDiscovery: Date?
    @ObservationIgnored private var discoveryLoop: Task<Void, Never>?

    /// Çalışan Claude süreçlerini arada bir yeniden tarar: kaçırılan oturumlar eklenir, kapanan/durdurulanlar kalkar, boşta süresi
    /// güncellenir. Arayüz açıkken (gözlemci varken) 30 sn'de bir, değilse 3 dk'da bir; tek tolerance'lı uyku, boşta CPU yok.
    func startDiscoveryLoop(interval: (@MainActor @Sendable () -> TimeInterval)? = nil,
                            scan: @escaping @Sendable () -> [ClaudeProcessDiscovery.Found] = { ClaudeProcessDiscovery.scan() }) {
        guard discoveryLoop == nil else { return }
        discoveryLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.discoverRunningSessions(force: true, scan: scan)
                let wait = interval?() ?? (self.shellObservers > 0 ? 30 : 180)
                try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(wait * 0.3))
            }
        }
    }

    func stopDiscoveryLoop() {
        discoveryLoop?.cancel()
        discoveryLoop = nil
    }

    /// Çalışan Claude CLI süreçlerinden "bekleyen oturum" üretir (Adalmon sonradan açıldıysa ya da oturum boşta olay üretmiyorsa).
    /// En çok 10 sn'de bir; tarama arka planda yapılır. `scan` testte sahtesiyle değiştirilir.
    func discoverRunningSessions(force: Bool = false, scan: @escaping @Sendable () -> [ClaudeProcessDiscovery.Found] = { ClaudeProcessDiscovery.scan() }) async {
        if !force, let last = lastDiscovery, Date().timeIntervalSince(last) < 10 { return }
        lastDiscovery = .now
        let found = await Task.detached(priority: .utility) { scan() }.value
        var next = state
        guard next.discoverSessions(found, now: .now) else { return }
        commit(next)
        refreshSummary()
        updateLivenessPolling()
        schedulePrune()
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
        updateShellPolling()
        lookUpUnknownModels(now: now, event: event)
    }

    /// Modeli bilinmeyen oturum için, hız sınırı izin veriyorsa arka plan kuyruğunda konuşma dosyasının yalnızca model alanını okur.
    /// Yalnızca olay gelince tetiklenir (zamanlayıcı yok); model bilinince durur. Stop/SubagentStop/SessionEnd olayları geri
    /// çekilmeyi atlayan (olay türü başına bir) zorunlu deneme yapar; PostToolUse ilk denemelerde 5 sn aralık kullanır.
    private func lookUpUnknownModels(now: Date, event: AgentEvent) {
        guard modelResolver != nil else { return }
        let name = event.name
        let force: String? = switch name {
        case .stop, .subagentStop, .sessionEnd: event.event
        default: nil
        }
        var ids = state.sessionsWithUnknownModel
        if name == .sessionEnd { ids += state.endedSessionsWithUnknownModel.filter { $0 == event.sessionID } }
        for id in ids.sorted() where lookups.shouldAttempt(id, now: now, fast: name == .postToolUse, force: force) {
            startLookup(id)
        }
    }

    private func startLookup(_ id: String) {
        guard let resolver = modelResolver else { return }
        Task.detached(priority: .utility) { [weak self] in
            let model = resolver.latestModel(sessionID: id)
            await self?.finishLookup(id, model: model)
        }
    }

    /// Kapanış sonrası görünür kalma süresinde model hâlâ bilinmiyorsa tek bir son deneme (kısa gecikmeyle, dosya yazımı otursun).
    static let finalLookupDelay: TimeInterval = 5

    private func scheduleFinalLookup(_ id: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.finalLookupDelay), tolerance: .seconds(1))
            guard let self, let s = self.state.sessions[id], s.status == .ended, s.badge == .unknown,
                  self.lookups.shouldAttempt(id, now: .now, force: "final") else { return }
            self.startLookup(id)
        }
    }

    private func finishLookup(_ id: String, model: String?) {
        var next = state
        let adopted = model.map { next.adoptTranscriptModel($0, for: id) } ?? false
        lookups.finish(id, found: model != nil, now: .now)
        if adopted { commit(next) }
        else if model == nil, state.sessions[id]?.status == .ended, state.sessions[id]?.badge == .unknown { scheduleFinalLookup(id) }
    }

    func prune(now: Date = .now) {
        var next = state
        let droppedSessions = next.prune(now: now)
        let droppedSubagents = next.pruneSubagents(now: now)
        guard !droppedSessions.isEmpty || droppedSubagents else { return }
        commit(next)
        lookups.retain(Set(state.sessions.keys))
        refreshSummary()
        updateLivenessPolling()
        updateShellPolling()
    }

    /// Pid'li oturumların süreçlerini bir kez yoklar; ölü bulunanlar kapanır (kısa süre sonra düşer). Zamanlayıcı bunu çağırır.
    func pollLiveness(now: Date = .now) {
        var next = state
        if !next.applyLiveness(using: probe, now: now).isEmpty { commit(next); refreshSummary() }
        else if next != state { commit(next) } // yalnızca süreç başlangıcı kaydedildi
        schedulePrune()
        updateLivenessPolling()
        updateShellPolling()
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
        shellTask?.cancel()
        shellTask = nil
        stopDiscoveryLoop()
        dormancyTask?.cancel()
        dormancyTask = nil
        dormancyDue = nil
        dockOverrides = [:]
        commit(AgentState())
        lookups.removeAll()
        lastEventAt = nil
        refreshSummary()
    }

    private func commit(_ next: AgentState) {
        state = next
        tidyDockOverrides()
        scheduleDormancy()
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
