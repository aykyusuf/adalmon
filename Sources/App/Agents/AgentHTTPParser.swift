import Foundation

/// Yerel dinleyicinin minimal HTTP/1.1 ayrıştırıcısı. Girdi güvenilmezdir: yalnızca `POST /v1/event`, `Content-Length` zorunlu,
/// gövde en çok 16 KB, başlıklar en çok 8 KB, `X-Adalmon-Token` sabit zamanlı karşılaştırılır. Saf mantık (ağ yok, testli).
enum AgentHTTPParser {
    static let maxBody = 16 * 1024
    static let maxHeader = 8 * 1024
    static let path = "/v1/event"
    static let tokenHeader = "x-adalmon-token"

    enum Outcome: Equatable, Sendable {
        /// Henüz tam istek yok; daha fazla bayt bekle.
        case needMore
        /// Geçerli, yetkili olay → 204.
        case event(AgentEvent)
        /// Reddedildi: durum kodu (yanıt gövdesi her zaman boş).
        case reject(Int)
    }

    static func parse(_ buffer: Data, token: String) -> Outcome {
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
        guard requestLine[1] == path else { return .reject(404) }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .reject(400) }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[key] != nil, key == "content-length" { return .reject(400) } // çift Content-Length
            headers[key] = value
        }
        guard headers["transfer-encoding"] == nil else { return .reject(400) }
        guard let provided = headers[tokenHeader], constantTimeEqual(provided, token), !token.isEmpty else { return .reject(401) }
        guard let lengthText = headers["content-length"] else { return .reject(411) }
        guard let length = Int(lengthText), length >= 0, lengthText.allSatisfy(\.isASCII) else { return .reject(400) }
        guard length <= maxBody else { return .reject(413) }

        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return .needMore }
        let body = buffer[bodyStart..<(bodyStart + length)]
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
        case .event, .needMore: (code, reason) = (204, "No Content")
        case .reject(let status): (code, reason) = (status, reasonPhrase(status))
        }
        return Data("HTTP/1.1 \(code) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }

    static func reasonPhrase(_ code: Int) -> String {
        switch code {
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 411: "Length Required"
        case 413: "Payload Too Large"
        case 431: "Request Header Fields Too Large"
        default: "Error"
        }
    }
}
