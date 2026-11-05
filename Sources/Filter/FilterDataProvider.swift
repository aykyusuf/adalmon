import Foundation
import Network
@preconcurrency import NetworkExtension
import os

private let log = Logger(subsystem: "com.yusufayik.adalmon", category: "filter")

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

    // MARK: Lifecycle

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
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
        let identity = resolver.identity(for: flow.sourceAppAuditToken)
        let (remoteHost, remotePort, isLoopback) = Self.remote(sock.remoteFlowEndpoint)

        // Saydam proxy'nin aktardığı bağlantılar `setMetadata` ile asıl uygulamaya atanır. Atanamadıysa
        // (kimlik bizim sysext'imizse) sayma: asıl akış zaten sayılır, çift sayım olmasın.
        if identity.signingID == IPC.filterBundleID { return .allow() }

        // Sınırlı uygulamanın QUIC'ini düşür: tarayıcı TCP'ye döner, o da saydam proxy'de sınırlanır.
        if ThrottlePolicy.shouldDropQUIC(app: identity.app, isUDP: sock.socketProtocol == IPPROTO_UDP,
                                         remotePort: remotePort, isLoopback: isLoopback,
                                         expensive: expensive, config: cfg) {
            log.debug("quic dropped \(identity.app, privacy: .public)")
            return .drop()
        }

        let kind: FlowKind
        if isLoopback {
            guard flow.direction == .outbound, cfg.proxyPorts.contains(remotePort),
                  !cfg.proxyOwnerPaths.contains(identity.executablePath) else {
                return .allow() // yerel IPC, sayılmaz
            }
            kind = .proxied
        } else if cfg.proxyOwnerPaths.contains(identity.executablePath) {
            kind = .proxyEgress
        } else {
            kind = .direct
        }

        let isMobile = expensive
        if isMobile, kind != .proxyEgress, cfg.blockedOnMobile.contains(identity.app) {
            log.notice("blocked \(identity.app, privacy: .public) -> \(remoteHost, privacy: .public)")
            return .drop()
        }

        let host = sock.remoteHostname.flatMap { $0.isEmpty ? nil : $0 } ?? remoteHost
        accumulator.begin(flow: flow.identifier,
                          state: .init(app: identity.app, signingID: identity.signingID, host: host, kind: kind))

        let verdict: NEFilterNewFlowVerdict
        if kind == .proxied {
            // İlk paketten CONNECT hedefini oku. Mobilde akışı izlemeye devam et (engellenebilsin diye).
            verdict = .filterDataVerdict(withFilterInbound: isMobile, peekInboundBytes: isMobile ? Self.mobileChunk : 0,
                                         filterOutbound: true, peekOutboundBytes: 2048)
        } else if isMobile, kind == .direct {
            verdict = .filterDataVerdict(withFilterInbound: true, peekInboundBytes: Self.mobileChunk,
                                         filterOutbound: false, peekOutboundBytes: 0)
        } else {
            verdict = .allow()
        }
        verdict.statisticsReportFrequency = .medium
        return verdict
    }

    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        if offset == 0, let host = ProxyTargetParser.host(from: readBytes) {
            accumulator.setHost(host, for: flow.identifier)
        }
        if shouldDrop(flow) { return .drop() }
        // Hedef okundu. Wi-Fi'de akışı tamamen serbest bırak (sıfır ek yük).
        // Mobilde gelen veri tarafı engelleme için izlenmeye devam eder; giden taraf seyrek kontrol edilir.
        let v: NEFilterDataVerdict = expensive
            ? NEFilterDataVerdict(passBytes: readBytes.count, peekBytes: 8 * 1024 * 1024)
            : .allow()
        v.statisticsReportFrequency = .medium
        return v
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
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

    /// Mobilde, engellenen bir uygulamanın açık akışını kes.
    private func shouldDrop(_ flow: NEFilterFlow) -> Bool {
        guard expensive, let state = accumulator.state(for: flow.identifier), state.kind != .proxyEgress else { return false }
        return XPCServer.shared.config.blockedOnMobile.contains(state.app)
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
