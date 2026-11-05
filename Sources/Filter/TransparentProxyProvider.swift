import Foundation
import Network
@preconcurrency import NetworkExtension
import os

private let log = Logger(subsystem: "com.example.adalmon", category: "throttle")

/// Uygulama bazlı hız sınırı için saydam proxy. Aynı system extension'da filtre ile birlikte çalışır.
///
/// - Sınırı olmayan her akış için `false` döner: sistem akışı doğrudan taşır (sıfır ek yük).
/// - Sınırlı uygulamaların TCP akışları (uygulama → SpoofDPI loopback akışları dahil) üstlenilir ve
///   uygulama × yön başına paylaşılan token kovasıyla hız sınırlı aktarılır.
/// - Fail-open: kurulum sırasında herhangi bir hata olursa akış kapatılır, asla askıda kalmaz.
/// - UDP üstlenilmez (kurallara girmez). Sınırlı uygulamaların QUIC'i filtrede düşürülür (TCP'ye geri dönüş).
final class TransparentProxyProvider: NETransparentProxyProvider, @unchecked Sendable {

    private let resolver = IdentityResolver()
    private let lock = NSLock()
    private var relays: [ObjectIdentifier: TCPRelay] = [:]

    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        let settings = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        var rules: [NENetworkRule] = [
            // Tüm giden TCP (loopback hariç — joker kural loopback'i kapsamaz).
            NENetworkRule(remoteNetworkEndpoint: nil, remotePrefix: 0, localNetworkEndpoint: nil, localPrefix: 0,
                          protocol: .TCP, direction: .outbound),
        ]
        // Uygulama → yerel proxy (SpoofDPI) akışları için açık loopback kuralları.
        for (host, prefix) in [("127.0.0.1", 32), ("::1", 128)] {
            let ep = Network.NWEndpoint.hostPort(host: .init(host), port: .any)
            rules.append(NENetworkRule(remoteNetworkEndpoint: ep, remotePrefix: prefix, localNetworkEndpoint: nil, localPrefix: 0,
                                       protocol: .TCP, direction: .outbound))
        }
        settings.includedNetworkRules = rules
        nonisolated(unsafe) let completionHandler = completionHandler
        setTunnelNetworkSettings(settings) { error in
            if let error { log.error("proxy settings failed: \(error.localizedDescription, privacy: .public)") }
            else { log.notice("transparent proxy started") }
            completionHandler(error)
        }
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        let all = lock.withLock { () -> [TCPRelay] in
            let r = Array(relays.values)
            relays.removeAll()
            return r
        }
        all.forEach { $0.cancel() }
        log.notice("transparent proxy stopped reason=\(reason.rawValue, privacy: .public) relays=\(all.count, privacy: .public)")
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        guard let tcp = flow as? NEAppProxyTCPFlow else { return false }
        let identity = resolver.identity(for: flow.metaData.sourceAppAuditToken)
        let (port, loopback) = Self.portAndLoopback(tcp.remoteFlowEndpoint)
        let server = XPCServer.shared
        guard ThrottlePolicy.shouldHandle(app: identity.app, executablePath: identity.executablePath,
                                          signingID: identity.signingID, isLoopback: loopback, remotePort: port,
                                          isTCP: true, expensive: server.isExpensive, config: server.config) else {
            return false
        }
        let relay = TCPRelay(flow: tcp, app: identity.app) { [weak self] r in
            guard let self else { return }
            _ = self.lock.withLock { self.relays.removeValue(forKey: ObjectIdentifier(r)) }
        }
        lock.withLock { relays[ObjectIdentifier(relay)] = relay }
        log.info("throttling \(identity.app, privacy: .public) -> \(String(describing: tcp.remoteFlowEndpoint), privacy: .public)")
        relay.start()
        return true
    }

    private static func portAndLoopback(_ ep: Network.NWEndpoint) -> (Int, Bool) {
        guard case let .hostPort(host, port) = ep else { return (0, false) }
        switch host {
        case .ipv4(let a): return (Int(port.rawValue), a.isLoopback)
        case .ipv6(let a): return (Int(port.rawValue), a.isLoopback)
        case .name(let n, _): return (Int(port.rawValue), n == "localhost")
        @unknown default: return (Int(port.rawValue), false)
        }
    }
}

/// Tek bir TCP akışının hız sınırlı aktarımı. Tüm durum `queue` üzerinde değişir.
/// Geri basınç: bir parça yazılıp tamamlanmadan sıradaki okunmaz; kova bekletmesi okumayı geciktirir.
final class TCPRelay: @unchecked Sendable {
    private let flow: NEAppProxyTCPFlow
    private let app: String
    private let queue = DispatchQueue(label: "adalmon.relay", qos: .utility)
    private let onFinish: @Sendable (TCPRelay) -> Void
    private var connection: NWConnection?
    private var finished = false
    private var upDone = false
    private var downDone = false

    private static let connectTimeout: TimeInterval = 15

    init(flow: NEAppProxyTCPFlow, app: String, onFinish: @escaping @Sendable (TCPRelay) -> Void) {
        self.flow = flow
        self.app = app
        self.onFinish = onFinish
    }

    func start() {
        let params = NWParameters.tcp
        params.preferNoProxies = true
        // Bağlantı, filtre ve diğer proxy'lere asıl uygulama olarak görünsün (sayım ve mobil engelleme doğru kalsın).
        flow.setMetadata(on: params)
        let conn = NWConnection(to: flow.remoteFlowEndpoint, using: params)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.openFlow()
            case .failed(let e):
                log.info("relay connect failed: \(e.localizedDescription, privacy: .public)")
                self.finish(error: e)
            case .waiting(let e):
                // Ağ yok / reddedildi: askıda kalma, kapat.
                log.info("relay waiting: \(e.localizedDescription, privacy: .public)")
                self.finish(error: e)
            case .cancelled:
                self.finish(error: nil)
            default:
                break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.connectTimeout) { [weak self] in
            guard let self, !self.finished, conn.state != .ready else { return }
            log.info("relay connect timeout")
            self.finish(error: nil)
        }
    }

    func cancel() {
        queue.async { [weak self] in self?.finish(error: nil) }
    }

    private func openFlow() {
        flow.open(withLocalFlowEndpoint: nil) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                if let error {
                    log.info("flow open failed: \(error.localizedDescription, privacy: .public)")
                    self.finish(error: error)
                    return
                }
                self.pumpUp()
                self.pumpDown()
            }
        }
    }

    // MARK: Uygulama → uzak (yükleme)

    private func pumpUp() {
        guard !finished else { return }
        flow.readData { [weak self] data, error in
            guard let self else { return }
            self.queue.async {
                guard !self.finished else { return }
                if error != nil { self.finish(error: error); return }
                guard let data, !data.isEmpty else {
                    // Uygulama yazmayı kapattı → uzak tarafa FIN.
                    self.connection?.send(content: nil, contentContext: .finalMessage, isComplete: true,
                                          completion: .contentProcessed { _ in })
                    self.upDone = true
                    self.finishIfBothDone()
                    return
                }
                let wait = RateLimiter.shared.delay(app: self.app, direction: .up, bytes: data.count)
                self.after(wait) {
                    self.connection?.send(content: data, completion: .contentProcessed { err in
                        self.queue.async {
                            if let err { self.finish(error: err); return }
                            self.pumpUp()
                        }
                    })
                }
            }
        }
    }

    // MARK: Uzak → uygulama (indirme)

    private func pumpDown() {
        guard !finished, let conn = connection else { return }
        let max = RateLimiter.shared.chunkSize(app: app, direction: .down)
        conn.receive(minimumIncompleteLength: 1, maximumLength: max) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            // `receive` tamamlayıcısı zaten `queue` üzerinde çalışır.
            guard !self.finished else { return }
            if let error { self.finish(error: error); return }
            guard let data, !data.isEmpty else { self.downChunkDone(isComplete: isComplete); return }
            let wait = RateLimiter.shared.delay(app: self.app, direction: .down, bytes: data.count)
            self.after(wait) {
                self.flow.write(data) { err in
                    self.queue.async {
                        guard !self.finished else { return }
                        if let err { self.finish(error: err); return }
                        self.downChunkDone(isComplete: isComplete)
                    }
                }
            }
        }
    }

    private func downChunkDone(isComplete: Bool) {
        guard !finished else { return }
        if isComplete {
            flow.closeWriteWithError(nil)
            downDone = true
            finishIfBothDone()
        } else {
            pumpDown()
        }
    }

    // MARK: Yardımcılar

    private func after(_ seconds: Double, _ work: @escaping @Sendable () -> Void) {
        if seconds <= 0.001 { work(); return }
        queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, !self.finished else { return }
            work()
        }
    }

    private func finishIfBothDone() {
        if upDone && downDone { finish(error: nil) }
    }

    private func finish(error: Error?) {
        guard !finished else { return }
        finished = true
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        flow.closeReadWithError(error)
        flow.closeWriteWithError(error)
        onFinish(self)
    }
}
