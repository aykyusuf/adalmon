import Foundation

/// Yerel proxy'ye giden ilk paketten hedef host'u çıkarır.
enum ProxyTargetParser {
    /// "CONNECT host:443 HTTP/1.1", "GET http://host/…" ya da SOCKS5 domain isteği.
    static func host(from data: Data) -> String? {
        let head = data.prefix(1024)
        if let text = String(data: head, encoding: .ascii) ?? String(data: head, encoding: .utf8) {
            let line = text.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let parts = line.split(separator: " ")
            if parts.count >= 2 {
                if parts[0] == "CONNECT" { return stripPort(String(parts[1])) }
                if let url = URL(string: String(parts[1])), let h = url.host { return h }
            }
        }
        // SOCKS5: VER=5 CMD=1 RSV=0 ATYP=3 LEN NAME PORT
        let b = [UInt8](data.prefix(300))
        if b.count > 5, b[0] == 5, b[1] == 1, b[3] == 3 {
            let len = Int(b[4])
            if b.count >= 5 + len { return String(decoding: b[5..<(5 + len)], as: UTF8.self) }
        }
        return nil
    }

    static func stripPort(_ hostPort: String) -> String {
        if hostPort.hasPrefix("["), let end = hostPort.firstIndex(of: "]") {
            return String(hostPort[hostPort.index(after: hostPort.startIndex)..<end])
        }
        if let colon = hostPort.lastIndex(of: ":"), hostPort.filter({ $0 == ":" }).count == 1 {
            return String(hostPort[..<colon])
        }
        return hostPort
    }
}
