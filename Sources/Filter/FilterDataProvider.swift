import Foundation
import Network
@preconcurrency import NetworkExtension
import os

private let log = Logger(subsystem: "com.example.adalmon", category: "filter")

/// Ağ akışlarını sayan içerik filtresi. Fail-open: her hata durumunda izin verir.
///
/// Sayım kuralı (SpoofDPI gibi yerel proxy'ler için):
/// - Uygulama → loopback:proxyPort akışı o uygulamanın internet kullanımıdır (`.proxied`).
/// - Proxy sürecinin dış akışları `.proxyEgress` olarak işaretlenir, uygulamalara eklenmez.
/// - Diğer loopback akışları yok sayılır.
final class FilterDataProvider: NEFilterDataProvider, @unchecked Sendable {

    private let resolver = IdentityResolver()
    private var accumulator: UsageAccumulator { XPCServer.shared.accumulator }
    /// Mobil verideyken izlenen akışlarda kaç byte'ta bir yeniden kontrol edileceği (engelleme için).
    private static let mobileChunk = 512 * 1024

    private var expensive: Bool { XPCServer.shared.isExpensive }

    /// Teşhis: filtre başladıktan sonraki ilk 30 sn'de her akış kararını logla (en fazla 500 satır).
    private let diagLock = NSLock()
    private var diagStart = Date.distantPast
    private var diagCount = 0
    private func diag(_ message: @autoclosure () -> String) {
        let ok: Bool = diagLock.withLock {
            guard Date.now.timeIntervalSince(diagStart) < 30, diagCount < 500 else { return false }
            diagCount += 1
            return true
        }
        if ok { let m = message(); log.notice("DIAG \(m, privacy: .public)") }
    }

    // MARK: Lifecycle

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        diagLock.withLock { diagStart = .now; diagCount = 0 }
        // Loopback akışları yalnızca açık kuralla filtreye gelir.
        var rules: [NEFilterRule] = []
        for (host, prefix) in [("127.0.0.1", 32), ("::1", 128)] {
            let ep = NWEndpoint.hostPort(host: .init(host), port: .any)
            rules.append(NEFilterRule(networkRule: NENetworkRule(destinationNetworkEndpoint: ep, prefix: prefix, protocol: .any),
                                      action: .filterData))
        }
        nonisolated(unsafe) let completionHandler = completionHandler
        apply(NEFilterSettings(rules: rules, defaultAction: .filterData)) { error in
            if let error { log.error("apply failed: \(error.localizedDescription, privacy: .public)") }
            else { log.notice("filter started") }
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.notice("filter stopped reason=\(reason.rawValue, privacy: .public)")
        completionHandler()
    }

    // MARK: Flows

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let sock = flow as? NEFilterSocketFlow else { return .allow() }
        let cfg = XPCServer.shared.config
        let t0 = DispatchTime.now().uptimeNanoseconds
        let identity = resolver.identity(for: flow.sourceAppAuditToken)
        let resolveMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        if resolveMs > 20 {
            log.notice("SLOW identity \(resolveMs, format: .fixed(precision: 1), privacy: .public) ms \(identity.executablePath, privacy: .public)")
        }
        let (remoteHost, remotePort, isLoopback) = Self.remote(sock.remoteFlowEndpoint)

        // Saydam proxy'nin aktardığı bağlantılar `setMetadata` ile asıl uygulamaya atanır. Atanamadıysa
        // (kimlik bizim sysext'imizse) sayma: asıl akış zaten sayılır, çift sayım olmasın.
        let proto = sock.socketProtocol == IPPROTO_UDP ? "udp" : "tcp"
        let dir = flow.direction == .outbound ? "out" : "in"
        if identity.signingID == IPC.filterBundleID { diag("self allow \(remoteHost):\(remotePort)"); return .allow() }

        // Sınırlı uygulamanın QUIC'ini düşür: tarayıcı TCP'ye döner, o da saydam proxy'de sınırlanır.
        if ThrottlePolicy.shouldDropQUIC(app: identity.app, isUDP: sock.socketProtocol == IPPROTO_UDP,
                                         remotePort: remotePort, isLoopback: isLoopback,
                                         expensive: expensive, config: cfg) {
            log.debug("quic dropped \(identity.app, privacy: .public)")
            diag("DROP-quic \(identity.app) \(remoteHost):\(remotePort)")
            return .drop()
        }

        let isOutbound = flow.direction == .outbound
        guard let kind = FlowPolicy.classify(isLoopback: isLoopback, isOutbound: isOutbound, remotePort: remotePort,
                                             executablePath: identity.executablePath, config: cfg) else {
            diag("allow-loopback \(identity.executablePath) \(dir) \(proto) \(remoteHost):\(remotePort)")
            return .allow() // yerel IPC, sayılmaz
        }

        let isMobile = expensive
        // Engel: orijin uygulamanın akışında (direct / proxied); proxyEgress asla. blockedAlways her ağda.
        if FlowPolicy.shouldBlock(app: identity.app, kind: kind, expensive: isMobile, config: cfg, signingID: identity.signingID) {
            log.notice("blocked \(identity.app, privacy: .public) -> \(remoteHost, privacy: .public)")
            diag("DROP-blocked \(identity.app) \(remoteHost)")
            return .drop()
        }
        // Veri Tasarrufu (yalnız mobil): izin listesi dışı uygulamanın yeni akışı. Karar orijin uygulamanın
        // loopback (proxied) akışında; SpoofDPI'ın egress'ine dokunulmaz.
        if FlowPolicy.shouldDropForDataSaver(app: identity.app, signingID: identity.signingID, executablePath: identity.executablePath,
                                             kind: kind, isOutbound: isOutbound, remotePort: remotePort,
                                             expensive: isMobile, config: cfg) {
            log.notice("data-saver drop \(identity.app, privacy: .public) -> \(remoteHost, privacy: .public):\(remotePort, privacy: .public)")
            diag("DROP-datasaver \(identity.app) \(remoteHost):\(remotePort)")
            return .drop()
        }

        let host = sock.remoteHostname.flatMap { $0.isEmpty ? nil : $0 } ?? remoteHost
        accumulator.begin(flow: flow.identifier,
                          state: .init(app: identity.app, signingID: identity.signingID, host: host, kind: kind,
                                       executablePath: identity.executablePath, remotePort: remotePort,
                                       isOutbound: isOutbound))

        // Veri gözetimi (`FlowPolicy.dataTap`). SpoofDPI'a giden (proxied) akışta YALNIZ ilk giden ≤1024 bayt
        // CONNECT/Host için gösterilir; `handleOutboundData` ayrıştırıp hemen `.allow()` verir (tutma yok, gelen taraf izlenmez).
        let verdict: NEFilterNewFlowVerdict
        switch FlowPolicy.dataTap(kind: kind, expensive: isMobile) {
        case .peekOutboundForTarget(let bytes):
            verdict = .filterDataVerdict(withFilterInbound: false, peekInboundBytes: 0,
                                         filterOutbound: true, peekOutboundBytes: bytes)
        case .mobileInbound:
            verdict = .filterDataVerdict(withFilterInbound: true, peekInboundBytes: Self.mobileChunk,
                                         filterOutbound: false, peekOutboundBytes: 0)
        case .none:
            verdict = .allow()
        }
        verdict.statisticsReportFrequency = .medium
        diag("\(kind) \(identity.executablePath) \(dir) \(proto) \(remoteHost):\(remotePort) host=\(host) mobile=\(isMobile)")
        return verdict
    }

    /// Yalnız `.proxied` akışlar için çağrılır (diğerlerinde giden veri filtrelenmez). Ayrıştır, her durumda HEMEN izin ver:
    /// yarım/bozuk/ikili veri de serbest, daha fazla bayt beklenmez, pass+peek döngüsü yok.
    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        let parsed = offset == 0 ? ProxyTargetParser.host(from: readBytes) : nil
        if let host = parsed { accumulator.setHost(host, for: flow.identifier) }
        diag("outData off=\(offset) n=\(readBytes.count) target=\(parsed ?? "-")")
        let v = NEFilterDataVerdict.allow()
        v.statisticsReportFrequency = .medium
        return v
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        diag("inData off=\(offset) n=\(readBytes.count)")
        if shouldDrop(flow) { return .drop() }
        let v: NEFilterDataVerdict = expensive
            ? NEFilterDataVerdict(passBytes: readBytes.count, peekBytes: Self.mobileChunk)
            : .allow()
        v.statisticsReportFrequency = .medium
        return v
    }

    override func handleInboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        .allow()
    }

    override func handleOutboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        .allow()
    }

    override func handle(_ report: NEFilterReport) {
        guard let flow = report.flow else { return }
        switch report.event {
        case .statistics, .flowClosed:
            accumulator.report(flow: flow.identifier,
                               totalIn: UInt64(report.bytesInboundCount),
                               totalOut: UInt64(report.bytesOutboundCount),
                               expensive: expensive,
                               closed: report.event == .flowClosed)
        default:
            break
        }
    }

    // MARK: Helpers

    /// Mobil doğrudan akışlarda (gelen veri izleniyor), sonradan engellenen / Veri Tasarrufu'na takılan uygulamanın açık akışını kes.
    private func shouldDrop(_ flow: NEFilterFlow) -> Bool {
        guard expensive, let state = accumulator.state(for: flow.identifier), state.kind != .proxyEgress else { return false }
        let cfg = XPCServer.shared.config
        return FlowPolicy.shouldBlock(app: state.app, kind: state.kind, expensive: true, config: cfg, signingID: state.signingID)
            || FlowPolicy.shouldDropForDataSaver(app: state.app, signingID: state.signingID, executablePath: state.executablePath,
                                                 kind: state.kind, isOutbound: state.isOutbound, remotePort: state.remotePort,
                                                 expensive: true, config: cfg)
    }

    private static func remote(_ ep: Network.NWEndpoint?) -> (host: String, port: Int, loopback: Bool) {
        guard case let .hostPort(host, port)? = ep else { return ("?", 0, false) }
        let h: String
        let loop: Bool
        switch host {
        case .ipv4(let a): h = "\(a)"; loop = a.isLoopback
        case .ipv6(let a): h = "\(a)"; loop = a.isLoopback
        case .name(let n, _): h = n; loop = n == "localhost"
        @unknown default: h = "\(host)"; loop = false
        }
        return (h, Int(port.rawValue), loop)
    }
}
