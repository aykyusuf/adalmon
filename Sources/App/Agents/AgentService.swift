import Foundation
import Observation

/// Claude ajanları özelliğinin koordinatörü: dinleyici yaşam döngüsü (yalnızca kullanıcı açtıysa), plugin kurulum durumu ve
/// canlı oturum modeli. Ayarlar kartı ve menü çubuğu öğesi bunu kullanır.
@MainActor @Observable
final class AgentService {
    enum ListenerState: Equatable {
        case off, starting, running(UInt16), failed(String)
    }

    let monitor = AgentMonitorModel()
    private(set) var listener: ListenerState = .off
    private(set) var pluginStatus: AgentPluginInstaller.PluginStatus = .unknown
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

    init(prefs: Preferences, installer: AgentPluginInstaller = AgentPluginInstaller()) {
        self.prefs = prefs
        self.installer = installer
    }

    var isEnabled: Bool { prefs.agentsEnabled }
    var port: UInt16? { if case .running(let port) = listener { port } else { nil } }

    /// Uygulama açılışında ve anahtar değişince: dinleyiciyi tercihe göre kur ya da kapat.
    func apply() {
        if prefs.agentsEnabled { startListening() } else { stopListening() }
    }

    func setEnabled(_ enabled: Bool) {
        prefs.agentsEnabled = enabled
        apply()
    }

    private func startListening() {
        guard server == nil else { return }
        token = installer.generator.readConfig()?.token ?? AgentPluginGenerator.makeToken()
        listener = .starting
        let monitor = monitor
        let server = AgentEventServer(
            token: token,
            onEvent: { event in Task { @MainActor in monitor.ingest(event) } },
            onState: { [weak self] state in Task { @MainActor in self?.handle(state) } })
        self.server = server
        let saved = prefs.agentsPort
        server.start(preferredPort: UInt16(exactly: saved).flatMap { AgentEventServer.portRange.contains($0) ? $0 : nil })
    }

    private func stopListening() {
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
            try? installer.generator.writeConfig(port: port, token: token)
        }
    }

    // MARK: Plugin

    func refreshPluginStatus() async {
        pluginStatus = await installer.status()
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
