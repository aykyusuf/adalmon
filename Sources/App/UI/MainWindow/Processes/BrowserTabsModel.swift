import AppKit
import Foundation
import Observation

/// "Tarayıcılar" sekmesinin durumu. Her şey isteğe bağlı (opt-in) ve yalnızca sekme görünürken çalışır:
/// - Safari: ayar kapalıyken HİÇ Apple olayı gönderilmez (izin durumu bile sorulmaz).
/// - Chrome: yalnızca kullanıcı "başlat"a bastıktan sonra, ayrı profilli hata ayıklama örneğine 127.0.0.1 üzerinden bağlanır.
@MainActor @Observable
final class BrowserTabsModel {
    static let safariEnabledKey = "browserTabs.safariListEnabled"
    static let chromeEnabledKey = "browserTabs.chromeDebugEnabled"
    /// Safari AppleScript yenileme aralığı (Safari'ye yük olmasın diye seyrek); Chrome yoklaması 5 sn.
    static let safariInterval: Duration = .seconds(10)
    static let chromeInterval: Duration = .seconds(5)
    static let launchWait: Duration = .seconds(20)

    enum SafariState: Equatable {
        case off, checking, notRunning, needsPermission, denied, loaded
        case failed(String)
    }

    enum ChromeState: Equatable {
        case off, idle, notInstalled, launching, connected
        case disconnected(String)
        case failed(String)
    }

    var safariEnabled: Bool {
        didSet {
            guard safariEnabled != oldValue else { return }
            defaults.set(safariEnabled, forKey: Self.safariEnabledKey)
            if !safariEnabled { clearSafari(.off) } else if safariState == .off { safariState = .checking }
        }
    }

    var chromeEnabled: Bool {
        didSet {
            guard chromeEnabled != oldValue else { return }
            defaults.set(chromeEnabled, forKey: Self.chromeEnabledKey)
            if !chromeEnabled { disconnectChrome(.off) } else if chromeState == .off { chromeState = .idle }
        }
    }

    private(set) var safariState: SafariState
    private(set) var safariTabs: [SafariTab] = []
    private(set) var safariMemory: SafariMemorySummary?
    private(set) var safariUpdated: Date?

    private(set) var chromeState: ChromeState
    private(set) var chromeTabs: [ChromeTabSnapshot] = []
    /// Bu hata ayıklama örneğinin renderer süreçleri (SystemInfo destekleniyorsa); nil = bilinmiyor.
    private(set) var chromeRenderer: ChromeRendererMemory?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let safari: any SafariTabsSource
    @ObservationIgnored private let safariPIDs: @MainActor () -> Set<Int32>
    @ObservationIgnored private let webContentScan: @Sendable (Set<Int32>) -> [WebContentProcess]
    @ObservationIgnored private let useNetwork: Bool
    /// Ağ oturumu ilk Chrome bağlantısında kurulur (görünüm her yeniden kurulduğunda URLSession açılmasın).
    @ObservationIgnored private var cachedTransport: URLSessionCDPTransport?
    private var transport: URLSessionCDPTransport? {
        guard useNetwork else { return nil }
        if let cachedTransport { return cachedTransport }
        let made = URLSessionCDPTransport()
        cachedTransport = made
        return made
    }
    @ObservationIgnored private var poller: ChromeTabsPoller?
    /// Tek uçuşlu yoklama: üst üste binen iki `poll()` aynı soketlerde birbirinin yanıtını yutmasın.
    @ObservationIgnored private var isPolling = false

    init(defaults: UserDefaults = .standard, safari: any SafariTabsSource = SafariAppleScriptSource(),
         safariPIDs: @escaping @MainActor () -> Set<Int32> = { SafariWebContentScanner.safariPIDs },
         webContentScan: @escaping @Sendable (Set<Int32>) -> [WebContentProcess] = { SafariWebContentScanner.scan(safariPIDs: $0) },
         useNetwork: Bool = true) {
        self.defaults = defaults
        self.safari = safari
        self.safariPIDs = safariPIDs
        self.webContentScan = webContentScan
        self.useNetwork = useNetwork
        let safariOn = defaults.bool(forKey: Self.safariEnabledKey)
        let chromeOn = defaults.bool(forKey: Self.chromeEnabledKey)
        safariEnabled = safariOn
        chromeEnabled = chromeOn
        safariState = safariOn ? .checking : .off
        chromeState = chromeOn ? .idle : .off
    }

    // MARK: Safari

    /// Sekme görünürken çalışır (`.task`); `isActive` false iken (pencere gizli / uygulama arkada) hiç çağrı yapmaz.
    func runSafari(isActive: @escaping @MainActor () -> Bool) async {
        while !Task.isCancelled && safariEnabled {
            if isActive() { await refreshSafari(ask: false) }
            try? await Task.sleep(for: Self.safariInterval, tolerance: .seconds(1))
        }
    }

    /// Kullanıcı düğmesi: izin penceresini (gerekirse) açar, sonra okur.
    func requestSafariPermission() async {
        guard safariEnabled else { return }
        await refreshSafari(ask: true)
    }

    func refreshSafari(ask: Bool) async {
        guard safariEnabled else { return }
        let permission = await safari.permission(ask: ask)
        guard safariEnabled else { return }
        switch permission {
        case .safariNotRunning: clearSafari(.notRunning); return
        case .notDetermined: clearSafari(.needsPermission); return
        case .denied: clearSafari(.denied); return
        case .granted: break
        case .unknown:
            // Durum okunamadı (meşgul / zaman aşımı / beklenmeyen kod): otomatik turda betik ÇALIŞTIRILMAZ (izin penceresi
            // yalnızca düğmeyle açılsın). Yüklü liste varsa korunur; yalnızca düğme (ask) devam eder.
            guard ask else {
                if safariState != .loaded { clearSafari(.needsPermission) }
                return
            }
        }
        do {
            let tabs = try await safari.fetchTabs()
            guard safariEnabled else { return }
            let pids = safariPIDs()
            let scan = webContentScan
            let processes = await Task.detached(priority: .utility) { scan(pids) }.value
            if safariTabs != tabs { safariTabs = tabs }
            let summary = SafariMemorySummary(processes: processes, tabCount: tabs.count)
            if safariMemory != summary { safariMemory = summary }
            safariUpdated = .now
            if safariState != .loaded { safariState = .loaded }
        } catch let error as SafariTabsError {
            switch error {
            case .notRunning: clearSafari(.notRunning)
            case .permissionDenied: clearSafari(.denied)
            case .permissionNotDetermined: clearSafari(.needsPermission)
            case .timeout where safariState == .loaded: break  // son liste kalır; sonraki turda yeniden denenir
            default: clearSafari(.failed(error.message))
            }
        } catch {
            clearSafari(.failed("Safari sekme listesi alınamadı."))
        }
    }

    private func clearSafari(_ state: SafariState) {
        if safariState != state { safariState = state }
        if !safariTabs.isEmpty { safariTabs = [] }
        if safariMemory != nil { safariMemory = nil }
    }

    // MARK: Chrome

    /// Sekme görünürken: önce mevcut hata ayıklama örneğini bulmaya çalışır (DevToolsActivePort), bağlıyken 5 sn'de bir
    /// yoklar. Bağlantı koparsa sessizce durur. Görünüm kaybolunca tüm soketler kapanır.
    func runChrome(isActive: @escaping @MainActor () -> Bool) async {
        guard chromeEnabled else { return }
        if chromeState == .idle, let port = ChromeDebugLauncher.activePort(), await isReachable(port: port) {
            connect(port: port)
        }
        while !Task.isCancelled && chromeEnabled {
            if chromeState == .connected && isActive() { await pollChrome() }
            try? await Task.sleep(for: Self.chromeInterval, tolerance: .milliseconds(500))
        }
        await poller?.shutdown()
        poller = nil
    }

    func launchChrome() async {
        guard chromeEnabled, chromeState != .launching, chromeState != .connected else { return }
        guard let app = ChromeDebugLauncher.chromeAppURL else { chromeState = .notInstalled; return }
        chromeState = .launching
        // Bu profil zaten açıksa yeniden başlatmadan bağlan (ikinci `open -n` yeni portu yok sayar).
        if let port = ChromeDebugLauncher.activePort(), await isReachable(port: port) {
            connect(port: port)
            return
        }
        guard let chosen = DebugPortPicker.pick(isFree: ChromeDebugLauncher.isPortFree) else {
            chromeState = .failed("Boş bir yerel port bulunamadı.")
            return
        }
        let path = app.path
        do {
            try await Task.detached(priority: .userInitiated) { try ChromeDebugLauncher.launch(appPath: path, port: chosen) }.value
        } catch {
            chromeState = .failed("Chrome başlatılamadı.")
            return
        }
        let deadline = ContinuousClock.now + Self.launchWait
        while ContinuousClock.now < deadline && !Task.isCancelled && chromeEnabled {
            // Gerçek port Chrome'un yazdığı dosyadan (aynı profil önceden açıksa seçilen port kullanılmaz).
            let port = ChromeDebugLauncher.activePort() ?? chosen
            if await isReachable(port: port) { connect(port: port); return }
            try? await Task.sleep(for: .milliseconds(500))
        }
        if chromeState == .launching {
            chromeState = .failed("Chrome başladı ama hata ayıklama portu yanıt vermedi. Chrome'u kapatıp yeniden deneyin.")
        }
    }

    private func connect(port: Int) {
        guard let transport else { return }
        poller = ChromeTabsPoller(port: port, http: transport, sockets: transport)
        chromeState = .connected
        Task { await pollChrome() }
    }

    private func isReachable(port: Int) async -> Bool {
        guard let transport, let url = CDPEndpointGuard.httpURL(port: port, path: "/json/version"),
              let data = try? await transport.get(url), let version = try? CDPCodec.version(from: data) else { return false }
        return version.webSocketDebuggerUrl != nil
    }

    private func pollChrome() async {
        guard let poller, !isPolling else { return }
        isPolling = true
        defer { isPolling = false }
        do {
            let snapshot = try await poller.poll()
            guard chromeState == .connected else { return }
            if chromeTabs != snapshot.tabs { chromeTabs = snapshot.tabs }
            var renderer: ChromeRendererMemory?
            if let processes = snapshot.processes {
                renderer = await Task.detached(priority: .utility) {
                    ChromeRendererMemory.make(processes: processes, path: { CoalitionAPI.path(of: $0) },
                                              footprint: { CoalitionAPI.processCounters(of: $0)?.counters.footprint })
                }.value
            }
            if chromeRenderer != renderer { chromeRenderer = renderer }
        } catch {
            disconnectChrome(.disconnected("Hata ayıklama Chrome'una bağlantı koptu (kapatılmış olabilir)."))
        }
    }

    private func disconnectChrome(_ state: ChromeState) {
        if let poller { Task { await poller.shutdown() } }
        poller = nil
        if chromeState != state { chromeState = state }
        if !chromeTabs.isEmpty { chromeTabs = [] }
        if chromeRenderer != nil { chromeRenderer = nil }
    }

    func resetChromeConnection() {
        guard chromeEnabled else { return }
        disconnectChrome(.idle)
    }
}
