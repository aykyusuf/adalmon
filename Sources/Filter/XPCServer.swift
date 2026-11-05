import Foundation
import Network
import os

private let log = Logger(subsystem: "com.example.adalmon", category: "xpc")

/// Filtrenin Mach servisi. Uygulama bağlanır, ayar gönderir ve kullanım tamponunu çeker (pull modeli).
final class XPCServer: NSObject, NSXPCListenerDelegate, FilterControl, @unchecked Sendable {
    static let shared = XPCServer()

    let accumulator = UsageAccumulator()
    private let lock = NSLock()
    private var _config = FilterConfig()
    private var listener: NSXPCListener?
    private let pathMonitor = NWPathMonitor()
    private var _pathExpensive = false

    var config: FilterConfig { lock.withLock { _config } }

    /// Mobil veri / hotspot (pahalı ya da kısıtlı yol) ya da kullanıcı elle işaretlemiş.
    /// Filtre ve saydam proxy aynı süreçte çalışır; ikisi de bunu kullanır.
    var isExpensive: Bool { lock.withLock { _pathExpensive || _config.forceMobile } }

    func start() {
        let l = NSXPCListener(machServiceName: IPC.machServiceName)
        l.setConnectionCodeSigningRequirement(IPC.appCodeRequirement)
        l.delegate = self
        l.resume()
        listener = l
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isExp = path.isExpensive || path.isConstrained
            self.lock.withLock { self._pathExpensive = isExp }
            log.notice("path expensive=\(isExp, privacy: .public)")
        }
        pathMonitor.start(queue: DispatchQueue(label: "adalmon.filter.path"))
        log.notice("XPC listener started")
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        c.exportedInterface = NSXPCInterface(with: FilterControl.self)
        c.exportedObject = self
        c.resume()
        return true
    }

    // MARK: FilterControl

    func updateConfig(_ json: Data, reply: @escaping (Bool) -> Void) {
        guard let cfg = try? JSONDecoder().decode(FilterConfig.self, from: json) else { reply(false); return }
        lock.withLock { _config = cfg }
        log.notice("config: proxyPorts=\(cfg.proxyPorts, privacy: .public) owners=\(cfg.proxyOwnerPaths.count, privacy: .public) blocked=\(cfg.blockedOnMobile.count, privacy: .public) limits=\(cfg.limits.count, privacy: .public)")
        reply(true)
    }

    func drainUsage(reply: @escaping (Data) -> Void) {
        let buckets = accumulator.drain()
        reply((try? JSONEncoder().encode(buckets)) ?? Data("[]".utf8))
    }

    func ping(reply: @escaping (String) -> Void) {
        reply(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
    }
}
