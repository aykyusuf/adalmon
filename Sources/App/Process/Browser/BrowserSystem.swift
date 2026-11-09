import AppKit
import CoreServices
import Darwin
import Foundation

// MARK: Safari (AppleScript)

/// Safari sekme kaynağı (testlerde sahtesi kullanılır).
/// Sekmede kısa JS döngüsü çalıştırma sonucu (sekme ↔ süreç eşlemesi için).
enum SafariSpinResult: Equatable, Sendable {
    case ok
    /// Develop menüsündeki "Apple Events'ten JavaScript'e izin ver" kapalı.
    case javascriptDisabled
    case failed(Int)
}

protocol SafariTabsSource: Sendable {
    /// `ask` false iken izin penceresi AÇILMAZ (yalnızca durum okunur); true yalnızca kullanıcı düğmeye bastığında.
    func permission(ask: Bool) async -> SafariAutomationPermission
    func fetchTabs() async throws -> [SafariTab]
    /// `window`/`index`: `SafariTab`'daki 1'den başlayan sıra. Sayfanın içeriğine dokunmayan ≈`milliseconds` ms'lik bir döngü çalıştırır.
    func spin(window: Int, index: Int) async -> SafariSpinResult
}

extension SafariTabsSource {
    func spin(window: Int, index: Int) async -> SafariSpinResult { .failed(-1) }
}

/// NSAppleScript ile Safari sekme listesi. Ana thread'i bloklamaz: tüm Apple olayları kendi seri kuyruğunda, tek uçuşlu;
/// Swift tarafında zaman aşımı (geç gelen sonuç atılır). NSAppleScript nesnesi kuyruğun içinde oluşturulur.
final class SafariAppleScriptSource: SafariTabsSource, @unchecked Sendable {
    static let safariBundleID = "com.apple.Safari"
    private let queue = DispatchQueue(label: "\(AdalmonIdentity.appBundleID).safari-tabs", qos: .utility)
    private let lock = NSLock()
    private var busy = false
    private let timeout: Double

    init(timeout: Double = Double(SafariTabsScript.timeoutSeconds) + 2) { self.timeout = timeout }

    static var isSafariRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: safariBundleID).isEmpty
    }

    func permission(ask: Bool) async -> SafariAutomationPermission {
        // Safari çalışmıyorsa hiçbir Apple olayı gönderilmez (Safari başlatılmasın).
        guard Self.isSafariRunning else { return .safariNotRunning }
        let status: Int32? = await run(timeout: ask ? nil : timeout) {
            let target = NSAppleEventDescriptor(bundleIdentifier: Self.safariBundleID)
            guard let desc = target.aeDesc else { return Int32(-1) }
            return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        }
        guard let status else { return .unknown(-1712) }
        return SafariAutomationPermission.from(status: status)
    }

    func fetchTabs() async throws -> [SafariTab] {
        guard Self.isSafariRunning else { throw SafariTabsError.notRunning }
        let outcome: Result<String, SafariTabsError>? = await run(timeout: timeout) {
            guard let script = NSAppleScript(source: SafariTabsScript.source) else { return .failure(.scriptFailed(-1)) }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error {
                let code = (error[NSAppleScript.errorNumber] as? Int) ?? -1
                return .failure(SafariTabsError.from(appleScriptError: code))
            }
            return .success(result.stringValue ?? "")
        }
        guard let outcome else { throw SafariTabsError.timeout }
        let output = try outcome.get()
        if SafariTabsScript.isNotRunning(output) { throw SafariTabsError.notRunning }
        return SafariTabsScript.parse(output)
    }

    func spin(window: Int, index: Int) async -> SafariSpinResult {
        guard Self.isSafariRunning else { return .failed(-600) }
        let source = "tell application \"Safari\" to do JavaScript \"\(TabProcessProbe.spinSource)\" in tab \(index) of window \(window)"
        let outcome: SafariSpinResult? = await run(timeout: 6) {
            guard let script = NSAppleScript(source: source) else { return .failed(-1) }
            var error: NSDictionary?
            _ = script.executeAndReturnError(&error)
            guard let error else { return .ok }
            let message = (error[NSAppleScript.errorMessage] as? String) ?? ""
            if message.localizedCaseInsensitiveContains("JavaScript") { return .javascriptDisabled }
            return .failed((error[NSAppleScript.errorNumber] as? Int) ?? -1)
        }
        return outcome ?? .failed(-1712)
    }

    /// Kuyrukta çalıştırır; `timeout` dolarsa nil döner (iş arka planda biter, sonucu atılır). Önceki çağrı hâlâ sürüyorsa
    /// yenisi kuyruğa eklenmez (nil).
    private func run<T: Sendable>(timeout: Double?, _ work: @escaping @Sendable () -> T) async -> T? {
        let acquired = lock.withLock {
            if busy { return false }
            busy = true
            return true
        }
        guard acquired else { return nil }
        let once = ResumeOnce<T?>()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            once.set(continuation)
            queue.async { [self] in
                let value = work()
                lock.lock(); busy = false; lock.unlock()
                once.resume(value)
            }
            if let timeout {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { once.resume(nil) }
            }
        }
    }
}

/// Devamın yalnızca bir kez sürdürülmesi (iş ile zaman aşımı yarışı).
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    func set(_ c: CheckedContinuation<T, Never>) {
        lock.lock(); continuation = c; lock.unlock()
    }

    func resume(_ value: T) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}

// MARK: Safari WebContent süreçleri

enum SafariWebContentScanner {
    /// Safari'nin sorumlu olduğu WebContent süreçleri ve ayak izleri (~birkaç ms; yalnızca bölüm görünürken çağrılır).
    static func scan(safariPIDs: Set<Int32>) -> [WebContentProcess] {
        SafariWebContentFilter.select(pids: CoalitionAPI.listPIDs(), safariPIDs: safariPIDs,
                                      path: { CoalitionAPI.path(of: $0) },
                                      responsible: { CoalitionAPI.responsiblePID(for: $0) },
                                      footprint: { CoalitionAPI.processCounters(of: $0)?.counters.footprint })
    }

    @MainActor static var safariPIDs: Set<Int32> {
        Set(NSRunningApplication.runningApplications(withBundleIdentifier: SafariAppleScriptSource.safariBundleID).map(\.processIdentifier))
    }
}

// MARK: Chrome başlatma

enum ChromeDebugLauncher {
    enum LaunchError: Error, Equatable {
        case notInstalled
        case noFreePort
        case launchFailed(Int32)
    }

    @MainActor static var chromeAppURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChromeDebugConfig.bundleID)
    }

    static var userDataDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return ChromeDebugConfig.userDataDirectory(applicationSupport: support)
    }

    /// `DevToolsActivePort` dosyasındaki port (Chrome yazar; eski bir dosya da olabilir, bağlantıyla doğrulanır).
    static func activePort(userDataDir: URL = userDataDirectory) -> Int? {
        let file = userDataDir.appendingPathComponent(DevToolsActivePort.fileName)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return DevToolsActivePort.parse(text)
    }

    /// 127.0.0.1:port bağlanılabilir mi (bind denemesi; SO_REUSEADDR yok, dinleyen varsa başarısız).
    static func isPortFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return rc == 0
    }

    /// Ayrı profille yeni bir Chrome örneği başlatır (açık Chrome kapatılmaz). Kabuk kullanılmaz: argüman dizisi.
    static func launch(appPath: String, port: Int, userDataDir: URL = userDataDirectory) throws {
        try FileManager.default.createDirectory(at: userDataDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ChromeDebugConfig.openArguments(appPath: appPath, port: port, userDataDir: userDataDir.path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw LaunchError.launchFailed(process.terminationStatus) }
    }
}
