import Foundation

/// Yerel proxy'ye (SpoofDPI vb.) giden ilk giden baytlardan hedef host'u çıkarır. Saf ve sınırlı:
/// en fazla `maxInspectBytes` bayta bakar, tek geçişte biter, hiçbir şey beklemez.
///
/// Desteklenen biçimler (ilk satır):
/// - `CONNECT host:443 HTTP/1.1` (HTTPS; yöntem büyük/küçük harf duyarsız), IPv6 için `[::1]:443`
/// - `GET http://host[:port]/yol HTTP/1.1` (mutlak URI) ya da, satır `/yol` ise, aynı pakette gelen `Host:` başlığı
/// - SOCKS5 CONNECT isteği (ATYP=3, alan adı). Not: SOCKS5'te istek ilk pakette değil, selamlaşmadan sonra gelir;
///   filtre ilk paketten sonra serbest bıraktığı için pratikte yalnız istek ilk pakette ise yakalanır.
///
/// Satır henüz tamamlanmadıysa (CRLF/LF yok ve ` HTTP/1.` görülmedi) `nil` döner: yarım bir host ("exa") asla üretilmez.
enum ProxyTargetParser {
    /// Bakılan en fazla bayt (filtrenin peek boyutuyla aynı).
    static let maxInspectBytes = 1024

    static func host(from data: Data) -> String? {
        let b = [UInt8](data.prefix(maxInspectBytes))
        guard let first = b.first else { return nil }
        if first == 0x05 { return socks5Host(b) }
        return httpHost(b)
    }

    // MARK: HTTP

    private static let lf: UInt8 = 0x0A
    private static let cr: UInt8 = 0x0D
    private static let space: UInt8 = 0x20

    private static func httpHost(_ b: [UInt8]) -> String? {
        let lineEndIdx = b.firstIndex(of: lf)
        let lineBytes = Array(b[..<(lineEndIdx ?? b.count)]).trimmingTrailingCR()
        // Yalnız yazdırılabilir ASCII (TLS ClientHello vb. ikili veri burada elenir).
        guard !lineBytes.isEmpty, lineBytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
        let line = String(decoding: lineBytes, as: UTF8.self)
        // Satır tamam mı? LF görüldü ya da sürüm belirteci geldi.
        guard lineEndIdx != nil || line.contains(" HTTP/1.") else { return nil }

        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        guard method.count >= 3, method.count <= 10, method.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let target = String(parts[1])

        if method.uppercased() == "CONNECT" {
            return normalized(stripPort(target))
        }
        let lower = target.lowercased()
        for scheme in ["http://", "https://"] where lower.hasPrefix(scheme) {
            var authority = target.dropFirst(scheme.count)
            if let end = authority.firstIndex(where: { "/?#".contains($0) }) { authority = authority[..<end] }
            if let at = authority.lastIndex(of: "@") { authority = authority[authority.index(after: at)...] }
            return normalized(stripPort(String(authority)))
        }
        if target.hasPrefix("/") || target == "*" {
            return hostHeader(b, afterLineEnd: lineEndIdx)
        }
        return nil
    }

    /// İlk satırdan sonra, aynı pakette tamamlanmış bir `Host:` başlığı.
    private static func hostHeader(_ b: [UInt8], afterLineEnd idx: Int?) -> String? {
        guard let idx, idx + 1 < b.count else { return nil }
        var start = idx + 1
        while start < b.count {
            guard let end = b[start...].firstIndex(of: lf) else { return nil } // yarım başlık: bekleme
            let raw = Array(b[start..<end]).trimmingTrailingCR()
            if raw.isEmpty { return nil } // başlıkların sonu
            if let colon = raw.firstIndex(of: 0x3A),
               String(decoding: raw[..<colon], as: UTF8.self).lowercased() == "host" {
                let value = String(decoding: raw[(colon + 1)...], as: UTF8.self).trimmingCharacters(in: .whitespaces)
                return normalized(stripPort(value))
            }
            start = end + 1
        }
        return nil
    }

    // MARK: SOCKS5

    /// VER=5 CMD=1 RSV=0 ATYP=3 LEN NAME PORT
    private static func socks5Host(_ b: [UInt8]) -> String? {
        guard b.count > 5, b[1] == 1, b[3] == 3 else { return nil }
        let len = Int(b[4])
        guard len > 0, b.count >= 5 + len else { return nil }
        return normalized(String(decoding: b[5..<(5 + len)], as: UTF8.self))
    }

    // MARK: Yardımcılar

    static func stripPort(_ hostPort: String) -> String {
        if hostPort.hasPrefix("["), let end = hostPort.firstIndex(of: "]") {
            return String(hostPort[hostPort.index(after: hostPort.startIndex)..<end])
        }
        if let colon = hostPort.lastIndex(of: ":"), hostPort.filter({ $0 == ":" }).count == 1 {
            return String(hostPort[..<colon])
        }
        return hostPort
    }

    /// Geçerli host mu (harf/rakam . - _ ve IPv6 için : %), en çok 253 karakter. Küçük harfe çevirir.
    private static func normalized(_ host: String) -> String? {
        let h = host.lowercased()
        guard !h.isEmpty, h.utf8.count <= 253 else { return nil }
        let ok = h.utf8.allSatisfy { c in
            (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7A) || c == 0x2E || c == 0x2D || c == 0x5F || c == 0x3A || c == 0x25
        }
        return ok ? h : nil
    }
}

private extension Array where Element == UInt8 {
    func trimmingTrailingCR() -> [UInt8] {
        last == 0x0D ? Array(dropLast()) : self
    }
}
