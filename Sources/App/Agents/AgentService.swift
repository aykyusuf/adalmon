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

    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private var installer: AgentPluginInstaller
    @ObservationIgnored private var server: AgentEventServer?
    @ObservationIgnored private var token = ""
    /// Tarayıcı görünümü: dinleyici iş parçacığı ile ana aktör arasındaki köprü ve durum → JSON üreticisi (özellik açılınca kurulur).
    @ObservationIgnored private let web = AgentWebStore()
    @ObservationIgnored private var webBuilder: AgentWebSnapshotBuilder?

    init(prefs: Preferences, installer: AgentPluginInstaller = AgentPluginInstaller()) {
        self.prefs = prefs
        self.installer = installer
        monitor.onStateChange = { [weak self] _ in self?.publishWeb() }
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

    /// Yalnızca durum değişince (monitor.onStateChange) çalışır; özellik kapalıyken hiçbir şey üretmez.
    private func publishWeb() {
        guard prefs.agentsWebEnabled, server != nil, let webBuilder else { return }
        let data = webBuilder.snapshot(sessions: monitor.state.orderedSessions)
        web.setState(data)
        server?.broadcast(data)
    }

    private func startListening() {
        guard server == nil else { return }
        token = installer.generator.readConfig()?.token ?? AgentPluginGenerator.makeToken()
        listener = .starting
        let monitor = monitor
        let prefs = prefs
        let server = AgentEventServer(
            token: token,
            web: web,
            onEvent: { event in
                Task { @MainActor in
                    // Savunma: hedef anahtarı kapalıysa (eski/elle değiştirilmiş betik gönderse bile) hedef atılır.
                    var event = event
                    if !prefs.agentsShowTargets { event.target = nil }
                    monitor.ingest(event)
                }
            },
            onState: { [weak self] state in Task { @MainActor in self?.handle(state) } })
        self.server = server
        let saved = prefs.agentsPort
        server.start(preferredPort: UInt16(exactly: saved).flatMap { AgentEventServer.portRange.contains($0) ? $0 : nil })
        web.setEnabled(prefs.agentsWebEnabled)
        prepareWeb()
    }

    private func stopListening() {
        web.setEnabled(false)
        server?.stop()
        server = nil
        listener = .off
        monitor.reset()
    }

    private func handle(_ state: AgentEventServer.State) {
        guard server != nil else { return }
        switch state {
        case .stopped: listener = .off
        case .failed(let reason): listener = .failed(reason)
        case .running(let port):
            listener = .running(port)
            if prefs.agentsPort != Int(port) { prefs.agentsPort = Int(port) }
            // Betik port/token'ı bu dosyadan okur; port değişse de yeniden kurulum gerekmez.
            try? installer.generator.writeConfig(port: port, token: token, showTargets: prefs.agentsShowTargets)
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
