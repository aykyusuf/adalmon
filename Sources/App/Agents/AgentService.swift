import AppKit
import Foundation
import Observation

/// Claude ajanları özelliğinin koordinatörü: dinleyici yaşam döngüsü (yalnızca kullanıcı açtıysa), plugin kurulum durumu ve
/// canlı oturum modeli. Ayarlar kartı ve menü çubuğu öğesi bunu kullanır.
@MainActor @Observable
final class AgentService {
    enum ListenerState: Equatable {
        case off, starting, running(UInt16), failed(String)
    }

    let monitor = AgentMonitorModel(modelResolver: TranscriptModelResolver())
    /// Abonelik limitleri (Claude statusLine sarmalayıcısı → `/v1/limits`, Codex yerel dosya). Dinleyiciden bağımsız yaşar.
    let limits = SubscriptionLimitsModel()
    /// Ofiste cevap bekleyen izin/soru kartları (YALNIZCA bellek; içerik başka hiçbir yere yazılmaz).
    let decisions: PendingDecisionStore
    private(set) var listener: ListenerState = .off
    private(set) var pluginStatus: AgentPluginInstaller.PluginStatus = .unknown
    /// Kurulu plugin'in sürümü (`claude plugin list --json`); bilinmiyorsa nil.
    private(set) var installedVersion: String?
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    /// CLI bulunamadığında gösterilecek elle komutlar.
    private(set) var manualCommands: [String] = []
    /// Kurulumdan sonra: açık Claude oturumları plugin'i görmez, yeni oturum gerekir.
    private(set) var needsNewSession = false

    /// "Hattı test et" sonucu (hook betiği → dinleyici → izleyici zinciri) ve çalışıyor mu.
    private(set) var selfTest: AgentHookSelfTest.Result?
    private(set) var isSelfTesting = false

    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private var installer: AgentPluginInstaller
    @ObservationIgnored private var server: AgentEventServer?
    @ObservationIgnored private var token = ""
    /// Tarayıcı görünümü: dinleyici iş parçacığı ile ana aktör arasındaki köprü ve durum → JSON üreticisi (özellik açılınca kurulur).
    @ObservationIgnored private let web = AgentWebStore()
    @ObservationIgnored private var webBuilder: AgentWebSnapshotBuilder?
    /// Açık SSE akışı varken izleyici sayacına +1 yazılmış mı (arka plan işlemleri yalnızca tarayıcı görünümü açıkken örneklenir).
    @ObservationIgnored private var webObserving = false
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    /// Süreç taramasıyla bekleyen oturum bulma. Testte kapalıdır (test makinesindeki gerçek Claude süreçleri sonuçları bozmasın).
    @ObservationIgnored var discoveryEnabled = !AppEnvironment.isRunningTests

    init(prefs: Preferences, installer: AgentPluginInstaller = AgentPluginInstaller()) {
        self.prefs = prefs
        self.installer = installer
        self.decisions = PendingDecisionStore(auditURL: installer.generator.auditLogURL)
        monitor.onStateChange = { [weak self] _ in self?.publishWeb() }
        decisions.onChange = { [weak self] in
            guard let self else { return }
            self.monitor.setAttention(self.decisions.sessionIDs)
        }
    }

    // MARK: Ofisten cevapla (OFFICE-CTRL-01)

    /// decide.py Python gerektirir (kabuk yedeği yok); Python yoksa özellik kapalıdır ve ayarlar nedenini söyler.
    var controlAvailable: Bool { installer.generator.usesPython }
    /// Etkin: kullanıcı açtı VE Python var. config.json `controlEnabled` bunun aynasıdır (betik oradan okur).
    var isControlEnabled: Bool { prefs.agentsControlEnabled && controlAvailable }

    /// Denetim kaydı (JSONL, yalnızca üst veri); ayarlar "göster" düğmesi bunu Finder'da açar.
    var auditLogURL: URL { installer.generator.auditLogURL }

    func setControlEnabled(_ on: Bool) {
        prefs.agentsControlEnabled = on
        // Dinleyici çalışmıyorsa true yazılmaz (betik ölü porta bağlanmaya çalışmasın); `.running` olunca tercih yazılır.
        try? installer.generator.setControlEnabled(on && controlAvailable && port != nil)
        if !on { decisions.dismissAll() }
    }

    /// Kullanıcının tıklaması: karar tutulan bağlantıya yazılır (betik doğrulayıp Claude Code'a döndürür).
    func respond(_ id: UUID, _ verdict: DecisionVerdict) {
        decisions.resolve(id, verdict)
    }

    /// Dinleyiciden gelen karar isteği (ana aktörde). Kapalıysa ya da oturum bilinen/canlı değilse reddedilir (betik terminale bırakır).
    private func receiveDecision(_ request: DecisionRequest, id: UUID) {
        guard isControlEnabled, let session = monitor.state.sessions[request.sessionID], session.status != .ended,
              decisions.add(PendingDecision(id: id, request: request)) else {
            server?.respondHeld(id, response: AgentDecisionParser.response(status: 403))
            return
        }
    }

    var isEnabled: Bool { prefs.agentsEnabled }
    var port: UInt16? { if case .running(let port) = listener { port } else { nil } }
    var isWebEnabled: Bool { prefs.agentsWebEnabled }
    /// Tarayıcıda açılacak adres (token'lı; gizli tutulmalı). Dinleyici çalışmıyorsa ya da görünüm kapalıysa nil.
    var webURL: URL? {
        guard prefs.agentsWebEnabled, let port, !token.isEmpty else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/?t=\(token)")
    }
    /// Token'sız adres (ekranda gösterim için).
    var webDisplayAddress: String? { port.map { "http://127.0.0.1:\($0)/" } }

    /// Uygulama açılışında ve anahtar değişince: dinleyiciyi tercihe göre kur ya da kapat.
    func apply() {
        if prefs.agentsEnabled { startListening() } else { stopListening() }
    }

    func setEnabled(_ enabled: Bool) {
        prefs.agentsEnabled = enabled
        apply()
    }

    /// "Hedefi de göster" anahtarı: tercih + betiğin okuduğu config.json (betik değişmez, yeniden kurulum gerekmez).
    func setShowTargets(_ on: Bool) {
        prefs.agentsShowTargets = on
        try? installer.generator.setShowTargets(on)
        if !on { monitor.clearTargets() }
    }

    func setWebEnabled(_ enabled: Bool) {
        prefs.agentsWebEnabled = enabled
        web.setEnabled(enabled && server != nil)
        if enabled {
            prepareWeb()
        } else {
            server?.closeStreams()
        }
    }

    /// Düzeni (tek seferlik dosya okuma) ve planlayıcıyı kurar, ilk anlık görüntüyü yayar.
    private func prepareWeb() {
        guard prefs.agentsWebEnabled, server != nil else { return }
        if webBuilder == nil {
            guard let root = web.officeRoot, let built = OfficeWebLayout.build(officeRoot: root) else { return }
            web.setLayout(built.json)
            webBuilder = AgentWebSnapshotBuilder(seats: built.seats)
        }
        publishWeb()
    }

    /// Test/teşhis: tarayıcı görünümü için kaç kez anlık görüntü (JSON) üretildi.
    @ObservationIgnored private(set) var webSnapshotBuilds = 0

    /// Yalnızca durum değişince (monitor.onStateChange) çalışır; özellik kapalıyken hiçbir şey üretmez.
    /// Bağlı tarayıcı (SSE) yoksa JSON üretilmez, yalnızca bayat işaretlenir; ilk istemci bağlanınca bir kez üretilir (pil:
    /// her hook olayında tüm ofis görüntüsünü kurup kimseye göndermemek).
    private func publishWeb() {
        guard prefs.agentsWebEnabled, server != nil, let webBuilder else { return }
        guard webObserving else { web.markStale(); return }
        webSnapshotBuilds += 1
        let dock = monitor.dock
        let data = webBuilder.snapshot(sessions: dock.open, minimized: dock.minimized)
        web.setState(data)
        server?.broadcast(data)
    }

    private func startListening() {
        guard server == nil else { return }
        token = installer.generator.readConfig()?.token ?? AgentPluginGenerator.makeToken()
        listener = .starting
        let monitor = monitor
        let prefs = prefs
        let limits = limits
        let decisions = decisions
        let server = AgentEventServer(
            token: token,
            web: web,
            onEvent: { event in
                Task { @MainActor in
                    // Savunma: hedef anahtarı kapalıysa (eski/elle değiştirilmiş betik gönderse bile) hedef atılır.
                    var event = event
                    if !prefs.agentsShowTargets { event.target = nil }
                    monitor.ingest(event)
                    // Sarmalayıcıdan duyulmuş oturum etkinse Claude limit verisi taze sayılır (değer değişmediği için yeniden gönderilmez).
                    limits.noteClaudeActivity(sessionID: event.sessionID)
                    // Aynı oturum/ajanın sonraki olayı bekleyen kartı düşürür (terminalde cevaplanmış olabilir).
                    decisions.dismiss(matching: event)
                }
            },
            onState: { [weak self] state in Task { @MainActor in self?.handle(state) } },
            onLimits: { message in Task { @MainActor in limits.ingestClaude(message.limits, sessionID: message.sessionID) } },
            onDecision: { [weak self] request, id in Task { @MainActor in self?.receiveDecision(request, id: id) } },
            onHeldClosed: { id in Task { @MainActor in decisions.serverClosed(id) } })
        server.onStreamCount = { [weak self] count in Task { @MainActor in self?.setWebObserving(count > 0) } }
        decisions.responder = { [weak server] id, verdict in server?.respondHeld(id, response: AgentDecisionParser.response(for: verdict)) }
        decisions.releaser = { [weak server] id in server?.respondHeld(id, response: AgentDecisionParser.response(status: 204)) }
        self.server = server
        let saved = prefs.agentsPort
        server.start(preferredPort: UInt16(exactly: saved).flatMap { AgentEventServer.portRange.contains($0) ? $0 : nil })
        web.setEnabled(prefs.agentsWebEnabled)
        prepareWeb()
        // Hook betikleri port+token'ı config.json'dan okur. Başka bir işlem (ikinci örnek, test) dosyayı ezerse olaylar ölü porta
        // gider; uygulama öne her geldiğinde dosya bu örneğin değerleriyle karşılaştırılıp gerekirse geri yazılır.
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.repairConfigIfNeeded()
                    if let self, self.discoveryEnabled { Task { await self.monitor.discoverRunningSessions() } }
                }
            }
        }
    }

    /// Hat testi: GERÇEK hook betiğini yapay bir olayla çalıştırır ve izleyicinin olayı alıp almadığına bakar; ayrıca çalışan Claude
    /// oturumlarından kaçının olay gönderdiğini sayar. Gerçek bir oturum oluşturmaz.
    func runSelfTest() async {
        guard !isSelfTesting else { return }
        isSelfTesting = true
        defer { isSelfTesting = false }
        repairConfigIfNeeded()
        let before = monitor.lastEventAt
        var latency: Double?
        if case .running = listener {
            let started = ContinuousClock.now
            let script = installer.generator.activeScriptURL, config = installer.generator.configURL
            let launched = await Task.detached(priority: .userInitiated) { AgentHookSelfTest.fire(script: script, config: config) }.value
            if launched {
                for _ in 0..<40 {
                    if monitor.lastEventAt != before, monitor.lastEventAt != nil { latency = Double((ContinuousClock.now - started).components.attoseconds) / 1e15; break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        let live = Set(await Task.detached(priority: .utility) { ClaudeProcessDiscovery.scan().map(\.pid) }.value)
        // Olay göndermemiş ("bekleyen") oturumlar sayılmaz: yalnızca gerçek hook olayı almış oturumlar.
        let reporting = Set(monitor.state.sessions.values.filter { !$0.discovered }.compactMap(\.pid)).intersection(live).count
        if discoveryEnabled { await monitor.discoverRunningSessions(force: true) }
        selfTest = AgentHookSelfTest.evaluate(listenerRunning: { if case .running = listener { true } else { false } }(),
                                              pluginInstalled: pluginStatus == .installed || FileManager.default.fileExists(atPath: installer.generator.activeScriptURL.path),
                                              eventArrived: latency != nil, latencyMs: latency, liveClaudeProcesses: live.count, reportingProcesses: reporting, at: .now)
    }

    /// config.json bu örneğin port/token'ından farklıysa (başkası yazmışsa) geri yazar. Dinleyici çalışmıyorsa hiçbir şey yapmaz.
    @discardableResult
    func repairConfigIfNeeded() -> Bool {
        guard case .running(let port) = listener, !token.isEmpty else { return false }
        let current = installer.generator.readConfig()
        guard current?.port != port || current?.token != token else { return false }
        try? installer.generator.writeConfig(port: port, token: token, showTargets: prefs.agentsShowTargets, controlEnabled: isControlEnabled)
        return true
    }

    private func setWebObserving(_ on: Bool) {
        guard on != webObserving else { return }
        webObserving = on
        if on { monitor.addShellObserver() } else { monitor.removeShellObserver() }
        if on, web.isStale { publishWeb() }
    }

    private func stopListening() {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        setWebObserving(false)
        web.setEnabled(false)
        decisions.dismissAll()
        decisions.responder = nil
        decisions.releaser = nil
        server?.stop()
        server = nil
        listener = .off
        installer.generator.clearControlEnabled()
        monitor.reset()
    }

    /// Uygulama kapanırken: betik ölü bir dinleyiciye karar isteği göndermesin diye config.json `controlEnabled` kapatılır.
    func prepareForTermination() {
        installer.generator.clearControlEnabled()
    }

    private func handle(_ state: AgentEventServer.State) {
        guard server != nil else { return }
        switch state {
        case .stopped:
            listener = .off
            installer.generator.clearControlEnabled()
        case .failed(let reason):
            listener = .failed(reason)
            installer.generator.clearControlEnabled()
        case .running(let port):
            listener = .running(port)
            if prefs.agentsPort != Int(port) { prefs.agentsPort = Int(port) }
            if discoveryEnabled { monitor.startDiscoveryLoop() }
            // Betik port/token'ı bu dosyadan okur; port değişse de yeniden kurulum gerekmez.
            try? installer.generator.writeConfig(port: port, token: token, showTargets: prefs.agentsShowTargets, controlEnabled: isControlEnabled)
        }
    }

    // MARK: Plugin

    func refreshPluginStatus() async {
        pluginStatus = await installer.status()
        installedVersion = pluginStatus == .installed ? await installer.installedVersion() : nil
    }

    /// Kurulu plugin'in betikleri Adalmon'un üretecinden eskiyse (ör. `session_title` eklenmeden önce kurulmuş).
    var scriptsOutdated: Bool {
        guard pluginStatus == .installed, let installedVersion else { return false }
        return installedVersion != AgentPluginGenerator.version
    }

    func installPlugin() async {
        guard let port, !isBusy else {
            if !isBusy { errorMessage = "Önce \"Özelliği aç\" anahtarını açın; dinleyici çalışmıyor." }
            return
        }
        isBusy = true
        errorMessage = nil
        manualCommands = []
        defer { isBusy = false }
        do {
            try await installer.install(port: port, token: token)
            needsNewSession = true
        } catch let error as AgentPluginInstaller.InstallError {
            errorMessage = error.errorDescription
            if error == .cliNotFound { manualCommands = installer.manualInstallCommands }
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshPluginStatus()
    }

    func updatePlugin() async {
        guard let port, !isBusy else {
            if !isBusy { errorMessage = "Önce \"Özelliği aç\" anahtarını açın; dinleyici çalışmıyor." }
            return
        }
        isBusy = true
        errorMessage = nil
        manualCommands = []
        defer { isBusy = false }
        do {
            try await installer.update(port: port, token: token)
            needsNewSession = true
        } catch let error as AgentPluginInstaller.InstallError {
            errorMessage = error.errorDescription
            if error == .cliNotFound { manualCommands = installer.manualUpdateCommands }
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshPluginStatus()
    }

    func uninstallPlugin() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        manualCommands = []
        defer { isBusy = false }
        do {
            try await installer.uninstall()
            needsNewSession = false
        } catch let error as AgentPluginInstaller.InstallError {
            errorMessage = error.errorDescription
            if error == .cliNotFound { manualCommands = installer.manualUninstallCommands }
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshPluginStatus()
    }
}
