import Foundation

/// `POST /v1/decision` ayrıştırıcısı (decide.py → Adalmon). Girdi güvenilmezdir; saf mantık (ağ yok, testli).
/// `/v1/limits` ile aynı kurallar: Origin başlığı varsa 403 (tarayıcıdan gelemez), Host yalnızca `127.0.0.1:<port>` / `localhost:<port>`
/// (aksi 421), `X-Adalmon-Token` sabit zamanlı, `Content-Length` zorunlu, gövde en çok 16 KB, başlıklar en çok 8 KB.
/// Burada "onayla" yolu YOKTUR: bu uç yalnızca bekleyen bir istek OLUŞTURUR; onay yalnızca Adalmon içinde tıklamayla verilir.
enum AgentDecisionParser {
    static let path = "/v1/decision"
    static let maxBody = AgentHTTPParser.maxBody
    static let maxHeader = AgentHTTPParser.maxHeader

    enum Outcome: Equatable, Sendable {
        case needMore
        case request(DecisionRequest)
        case reject(Int)
    }

    private static let requestLinePrefix = Data("POST \(path) ".utf8)

    /// Tampon bir `POST /v1/decision` isteğiyle mi başlıyor (sunucu bunu olay ayrıştırıcısına vermeden önce yönlendirir).
    static func isDecisionRequest(_ buffer: Data) -> Bool {
        buffer.starts(with: requestLinePrefix)
    }

    static func parse(_ buffer: Data, token: String, port: UInt16?) -> Outcome {
        let terminator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: terminator) else {
            return buffer.count > maxHeader ? .reject(431) : .needMore
        }
        guard headerEnd.lowerBound <= maxHeader else { return .reject(431) }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .reject(400) }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1."), requestLine[0] == "POST", requestLine[1] == path else { return .reject(400) }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .reject(400) }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[key] != nil, key == "content-length" { return .reject(400) }
            headers[key] = value
        }
        guard headers["transfer-encoding"] == nil else { return .reject(400) }
        guard headers["origin"] == nil else { return .reject(403) }
        if let port {
            let allowed = ["127.0.0.1:\(port)", "localhost:\(port)"]
            guard let host = headers["host"]?.lowercased(), allowed.contains(host) else { return .reject(421) }
        }
        guard let provided = headers[AgentHTTPParser.tokenHeader], AgentHTTPParser.constantTimeEqual(provided, token), !token.isEmpty else { return .reject(401) }
        guard let lengthText = headers["content-length"] else { return .reject(411) }
        guard let length = Int(lengthText), length >= 0, lengthText.allSatisfy(\.isASCII) else { return .reject(400) }
        guard length <= maxBody else { return .reject(413) }
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return .needMore }
        guard let request = DecisionRequest(json: Data(buffer[bodyStart..<(bodyStart + length)])) else { return .reject(400) }
        return .request(request)
    }

    /// Tutulan bağlantıya yazılan yanıt: karar varsa 200 + JSON, `release` ise 204 (betik çıktısız çıkar).
    static func response(for verdict: DecisionVerdict) -> Data {
        guard let body = verdict.wireJSON else { return response(status: 204) }
        var data = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        data.append(body)
        return data
    }

    /// Boş gövdeli yanıt (204 bırakma, 403 bilinmeyen oturum/kapalı, 429 üst sınır…).
    static func response(status: Int) -> Data {
        let reason = status == 204 ? "No Content" : status == 429 ? "Too Many Requests" : AgentHTTPParser.reasonPhrase(status)
        return Data("HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }
}
