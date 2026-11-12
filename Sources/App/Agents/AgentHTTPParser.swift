import Foundation

/// Yerel dinleyicinin minimal HTTP/1.1 ayrıştırıcısı. Girdi güvenilmezdir: yalnızca `POST /v1/event`, `Content-Length` zorunlu,
/// gövde en çok 16 KB, başlıklar en çok 8 KB, `X-Adalmon-Token` sabit zamanlı karşılaştırılır. Saf mantık (ağ yok, testli).
/// `POST /v1/limits` (statusLine sarmalayıcısı, abonelik limitleri): ek olarak Origin başlığı varsa 403 (tarayıcıdan gelemez),
/// `port` verilmişse Host yalnızca `127.0.0.1:<port>` / `localhost:<port>` (DNS rebinding) → aksi 421.
enum AgentHTTPParser {
    static let maxBody = 16 * 1024
    static let maxHeader = 8 * 1024
    static let path = "/v1/event"
    static let limitsPath = "/v1/limits"
    static let tokenHeader = "x-adalmon-token"

    enum Outcome: Equatable, Sendable {
        /// Henüz tam istek yok; daha fazla bayt bekle.
        case needMore
        /// Geçerli, yetkili olay → 204.
        case event(AgentEvent)
        /// Geçerli, yetkili abonelik limiti (Claude) → 204.
        case limits(ProviderLimits)
        /// Reddedildi: durum kodu (yanıt gövdesi her zaman boş).
        case reject(Int)
    }

    static func parse(_ buffer: Data, token: String, port: UInt16? = nil, now: Date = .now) -> Outcome {
        let terminator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: terminator) else {
            return buffer.count > maxHeader ? .reject(431) : .needMore
        }
        guard headerEnd.lowerBound <= maxHeader else { return .reject(431) }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .reject(400) }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .reject(400) }
        guard requestLine[0] == "POST" else { return .reject(405) }
        // Sorgu dizesi yok sayılmaz: yol birebir eşleşmeli.
        let isLimits = requestLine[1] == limitsPath
        guard requestLine[1] == path || isLimits else { return .reject(404) }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .reject(400) }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[key] != nil, key == "content-length" { return .reject(400) } // çift Content-Length
            headers[key] = value
        }
        guard headers["transfer-encoding"] == nil else { return .reject(400) }
        if isLimits {
            guard headers["origin"] == nil else { return .reject(403) }
            if let port {
                let allowed = ["127.0.0.1:\(port)", "localhost:\(port)"]
                guard let host = headers["host"]?.lowercased(), allowed.contains(host) else { return .reject(421) }
            }
        }
        guard let provided = headers[tokenHeader], constantTimeEqual(provided, token), !token.isEmpty else { return .reject(401) }
        guard let lengthText = headers["content-length"] else { return .reject(411) }
        guard let length = Int(lengthText), length >= 0, lengthText.allSatisfy(\.isASCII) else { return .reject(400) }
        guard length <= maxBody else { return .reject(413) }

        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return .needMore }
        let body = buffer[bodyStart..<(bodyStart + length)]
        if isLimits {
            guard let limits = ClaudeLimitsPayload.parse(Data(body), now: now) else { return .reject(400) }
            return .limits(limits)
        }
        guard let event = AgentEvent(json: Data(body)) else { return .reject(400) }
        return .event(event)
    }

    /// Bayt başına erken çıkış olmadan karşılaştırır (token zamanlama sızıntısı olmasın).
    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = x.count ^ y.count
        for i in 0..<max(x.count, y.count) {
            diff |= Int(i < x.count ? x[i] : 0) ^ Int(i < y.count ? y[i] : 0)
        }
        return diff == 0
    }

    /// Yanıt baytları: her zaman boş gövde (204 başarıda; hatada ilgili kod).
    static func response(for outcome: Outcome) -> Data {
        let (code, reason): (Int, String)
        switch outcome {
        case .event, .limits, .needMore: (code, reason) = (204, "No Content")
        case .reject(let status): (code, reason) = (status, reasonPhrase(status))
        }
        return Data("HTTP/1.1 \(code) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }

    static func reasonPhrase(_ code: Int) -> String {
        switch code {
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 411: "Length Required"
        case 413: "Payload Too Large"
        case 421: "Misdirected Request"
        case 431: "Request Header Fields Too Large"
        default: "Error"
        }
    }
}
