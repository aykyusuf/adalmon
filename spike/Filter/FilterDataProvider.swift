import Foundation
import Network
import NetworkExtension
import os
import Security

private let log = Logger(subsystem: "com.example.adalmon", category: "filter")

/// Spike: her akışı loglar, asla engellemez (fail-open).
/// Amaç: loopback (SpoofDPI proxy) akışları geliyor mu, CONNECT host okunabiliyor mu,
/// bayt raporları akış boyunca geliyor mu, audit token'lar nsurlsessiond'u gerçek app'e bağlıyor mu.
final class FilterDataProvider: NEFilterDataProvider, @unchecked Sendable {

    static let proxyPort = "8080"

    private struct FlowMeta {
        let app: String
        let appPid: Int32
        let procPid: Int32
        let procPath: String
        let remote: String
        let hostname: String
        let proto: String
        let direction: String
        var connectHost: String?
    }

    private let lock = NSLock()
    private var flows: [UUID: FlowMeta] = [:]

    // MARK: Lifecycle

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        // Varsayılan: her şey filterData. Loopback ancak açık kuralla gelir; hem yeni hem eski kurucuyu dene.
        var rules: [NEFilterRule] = []
        for host in ["127.0.0.1", "::1"] {
            let prefix = host.contains(":") ? 128 : 32
            if let ep = Optional(NWEndpoint.hostPort(host: .init(host), port: .any)) {
                let r = NENetworkRule(destinationNetworkEndpoint: ep, prefix: prefix, protocol: .any)
                rules.append(NEFilterRule(networkRule: r, action: .filterData))
            }
        }
        let settings = NEFilterSettings(rules: rules, defaultAction: .filterData)
        log.notice("startFilter rules=\(rules.count, privacy: .public)")
        apply(settings) { error in
            if let error {
                log.error("apply(new rules) failed: \(error.localizedDescription, privacy: .public)")
            }
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.notice("stopFilter reason=\(reason.rawValue, privacy: .public)")
        completionHandler()
    }

    // MARK: Flows

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let sock = flow as? NEFilterSocketFlow else {
            return Self.allowWithStats()
        }
        let appPid = Self.pid(from: flow.sourceAppAuditToken)
        let procPid = Self.pid(from: flow.sourceProcessAuditToken)
        let remote = Self.describe(sock.remoteFlowEndpoint)
        let meta = FlowMeta(
            app: Self.signingID(from: flow.sourceAppAuditToken),
            appPid: appPid,
            procPid: procPid,
            procPath: Self.path(for: procPid),
            remote: remote,
            hostname: sock.remoteHostname ?? "",
            proto: sock.socketProtocol == IPPROTO_UDP ? "udp" : (sock.socketProtocol == IPPROTO_TCP ? "tcp" : "\(sock.socketProtocol)"),
            direction: flow.direction == .outbound ? "out" : (flow.direction == .inbound ? "in" : "any"),
            connectHost: nil
        )
        lock.withLock { flows[flow.identifier] = meta }

        log.notice("NEW \(flow.identifier.uuidString.suffix(12), privacy: .public) app=\(meta.app, privacy: .public)[\(appPid, privacy: .public)] proc=\(meta.procPath, privacy: .public)[\(procPid, privacy: .public)] \(meta.proto, privacy: .public) \(meta.direction, privacy: .public) -> \(remote, privacy: .public) host=\(meta.hostname, privacy: .public)")

        // Proxy'ye giden outbound akış: ilk ~2KB'ı peek et, CONNECT host'u çıkar.
        if meta.direction == "out", Self.isProxy(sock.remoteFlowEndpoint) {
            let v = NEFilterNewFlowVerdict.filterDataVerdict(
                withFilterInbound: false, peekInboundBytes: 0,
                filterOutbound: true, peekOutboundBytes: 2048)
            v.statisticsReportFrequency = .medium
            return v
        }
        return Self.allowWithStats()
    }

    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        if offset == 0, let host = Self.parseProxyTarget(readBytes) {
            lock.withLock { flows[flow.identifier]?.connectHost = host }
            log.notice("CONNECT \(flow.identifier.uuidString.suffix(12), privacy: .public) target=\(host, privacy: .public)")
        } else {
            log.notice("PEEK \(flow.identifier.uuidString.suffix(12), privacy: .public) no target (\(readBytes.count, privacy: .public)B)")
        }
        let v = NEFilterDataVerdict.allow()
        v.statisticsReportFrequency = .medium
        return v
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        .allow()
    }

    override func handle(_ report: NEFilterReport) {
        guard let flow = report.flow else { return }
        let meta = lock.withLock { () -> FlowMeta? in
            let m = flows[flow.identifier]
            if report.event == .flowClosed { flows[flow.identifier] = nil }
            return m
        }
        let ev: String
        switch report.event {
        case .statistics: ev = "STAT"
        case .flowClosed: ev = "CLOSE"
        case .newFlow: ev = "NEWR"
        case .dataDecision: ev = "DATA"
        @unknown default: ev = "EV\(report.event.rawValue)"
        }
        let target = meta?.connectHost ?? meta?.hostname ?? ""
        log.notice("\(ev, privacy: .public) \(flow.identifier.uuidString.suffix(12), privacy: .public) app=\(meta?.app ?? "?", privacy: .public) proc=\(meta?.procPath ?? "?", privacy: .public) -> \(meta?.remote ?? "?", privacy: .public) target=\(target, privacy: .public) in=\(report.bytesInboundCount, privacy: .public) out=\(report.bytesOutboundCount, privacy: .public)")
    }

    // MARK: Helpers

    private static func allowWithStats() -> NEFilterNewFlowVerdict {
        let v = NEFilterNewFlowVerdict.allow()
        v.statisticsReportFrequency = .medium
        return v
    }

    private static func isProxy(_ ep: Network.NWEndpoint?) -> Bool {
        guard case let .hostPort(host, port)? = ep else { return false }
        let h = "\(host)"
        return (h == "127.0.0.1" || h == "::1" || h == "localhost") && "\(port.rawValue)" == proxyPort
    }

    private static func describe(_ ep: Network.NWEndpoint?) -> String {
        guard let ep else { return "nil" }
        if case let .hostPort(host, port) = ep { return "\(host):\(port.rawValue)" }
        return "\(ep)"
    }

    /// Audit token -> code signing identifier (örn. com.google.Chrome)
    private static func signingID(from token: Data?) -> String {
        guard let token else { return "?" }
        var code: SecCode?
        let attrs = [kSecGuestAttributeAudit: token] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else { return "?" }
        var st: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &st) == errSecSuccess, let st else { return "?" }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(st, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return "?" }
        return dict[kSecCodeInfoIdentifier as String] as? String ?? "?"
    }

    /// audit_token_t.val[5] == pid
    private static func pid(from token: Data?) -> Int32 {
        guard let token, token.count == MemoryLayout<audit_token_t>.size else { return -1 }
        return token.withUnsafeBytes { raw in
            raw.load(fromByteOffset: 5 * MemoryLayout<UInt32>.size, as: Int32.self)
        }
    }

    private static func path(for pid: Int32) -> String {
        guard pid > 0 else { return "?" }
        var buf = [CChar](repeating: 0, count: 4 * 1024)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return "pid\(pid)" }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// "CONNECT host:443 HTTP/1.1" veya "GET http://host/..." ya da SOCKS5 domain.
    static func parseProxyTarget(_ data: Data) -> String? {
        if let s = String(data: data.prefix(1024), encoding: .ascii) ?? String(data: data.prefix(1024), encoding: .utf8) {
            let line = s.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let parts = line.split(separator: " ")
            if parts.count >= 2 {
                if parts[0] == "CONNECT" { return String(parts[1]) }
                if let u = URL(string: String(parts[1])), let h = u.host { return h }
            }
        }
        // SOCKS5 CONNECT with domain (ATYP=3): VER CMD RSV ATYP LEN NAME PORT — selamlaşmadan sonra gelir, ilk pakette olmayabilir.
        let b = [UInt8](data.prefix(300))
        if b.count > 5, b[0] == 5, b[1] == 1, b[3] == 3 {
            let len = Int(b[4])
            if b.count >= 5 + len { return String(decoding: b[5..<(5 + len)], as: UTF8.self) }
        }
        return nil
    }
}
