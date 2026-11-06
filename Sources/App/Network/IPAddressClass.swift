import Foundation

/// Bir IP adresinin (v4/v6) ağ içindeki türü. Alan adı listelerinde yerel/loopback adresleri gizlemek için kullanılır.
enum IPAddressClass: Equatable, Sendable {
    /// 127.0.0.0/8, ::1
    case loopback
    /// 10/8, 172.16/12, 192.168/16, fc00::/7 (ULA), fec0::/10 (eski site-local)
    case privateNetwork
    /// 169.254/16, fe80::/10
    case linkLocal
    /// 100.64/10 (CGNAT / Tailscale)
    case sharedAddressSpace
    /// 224/4, ff00::/8 (mDNS dahil)
    case multicast
    /// 0/8, ::
    case unspecified
    /// 240/4 (yayın adresi 255.255.255.255 dahil)
    case reserved
    /// İnternette yönlendirilebilir adres.
    case publicAddress

    /// Yerel ağa ait (genel internet olmayan) mi? Loopback dahil değildir; o ayrıca ele alınır.
    var isLocalNetwork: Bool {
        switch self {
        case .privateNetwork, .linkLocal, .sharedAddressSpace, .multicast, .unspecified, .reserved: true
        case .loopback, .publicAddress: false
        }
    }

    /// Ayrıştırılmış adres: normalleştirilmiş metin (köşeli parantez, bölge soneki ve IPv4-mapped öneki atılmış) ve türü.
    struct Parsed: Equatable, Sendable {
        var text: String
        var kind: IPAddressClass
    }

    /// `host` bir IP adres değişmezi değilse nil. `[fe80::1]`, `fe80::1%en0` ve `::ffff:10.0.0.1` biçimlerini kabul eder.
    static func parse(_ host: String) -> Parsed? {
        var s = host.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("["), s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
        if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) }
        guard let first = s.first, first == ":" || first.isHexDigit else { return nil }

        var v4 = in_addr()
        if inet_pton(AF_INET, s, &v4) == 1 {
            let b = withUnsafeBytes(of: &v4) { Array($0) }
            return Parsed(text: s, kind: classifyV4(b))
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, s, &v6) == 1 {
            let b = withUnsafeBytes(of: &v6) { Array($0) }
            if b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xff, b[11] == 0xff { // ::ffff:a.b.c.d
                let mapped = Array(b[12..<16])
                return Parsed(text: mapped.map(String.init).joined(separator: "."), kind: classifyV4(mapped))
            }
            return Parsed(text: s.lowercased(), kind: classifyV6(b))
        }
        return nil
    }

    static func classify(_ host: String) -> IPAddressClass? { parse(host)?.kind }

    private static func classifyV4(_ b: [UInt8]) -> IPAddressClass {
        switch (b[0], b[1]) {
        case (127, _): .loopback
        case (10, _), (192, 168): .privateNetwork
        case (172, 16...31): .privateNetwork
        case (169, 254): .linkLocal
        case (100, 64...127): .sharedAddressSpace
        case (0, _): .unspecified
        case (224...239, _): .multicast
        case (240...255, _): .reserved
        default: .publicAddress
        }
    }

    private static func classifyV6(_ b: [UInt8]) -> IPAddressClass {
        if b[0..<15].allSatisfy({ $0 == 0 }) {
            if b[15] == 1 { return .loopback }
            if b[15] == 0 { return .unspecified }
        }
        if b[0] == 0xff { return .multicast }
        if b[0] == 0xfe, b[1] & 0xc0 == 0x80 { return .linkLocal }
        if b[0] & 0xfe == 0xfc { return .privateNetwork }
        if b[0] == 0xfe, b[1] & 0xc0 == 0xc0 { return .privateNetwork }
        return .publicAddress
    }
}
