import Foundation

/// Tarayıcı görünümü (canlı ofis) için GET/HEAD katmanı: saf mantık (ağ yok, testli). Yalnızca 127.0.0.1'de dinleyen aynı
/// dinleyiciye takılır; `POST /v1/event` yolu (`AgentHTTPParser`) değişmez. Girdi güvenilmezdir.
///
/// Kontrol sırası: özellik kapalı → 404; Host (DNS rebinding) → 421; Origin → 403; token → 401; yol → 404/405.
/// Token: `X-Adalmon-Token` başlığı ya da `?t=` (script/stylesheet/EventSource başlık gönderemez); sabit zamanlı karşılaştırılır.
enum AgentWebRouter {
    static let maxTarget = 2048
    static let maxSSEClients = 8
    static let tokenPlaceholder = "__ADALMON_TOKEN__"
    static let contentSecurityPolicy = "default-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

    struct Request: Equatable, Sendable {
        var method: String
        var target: String
        var headers: [String: String]

        var path: String { String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "") }
        var query: String? {
            let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count == 2 ? String(parts[1]) : nil
        }
    }

    enum ParseOutcome: Equatable, Sendable {
        case needMore
        case request(Request)
        case reject(Int)
    }

    struct Response: Equatable, Sendable {
        var status: Int
        var contentType: String
        var body: Data
        var headOnly = false

        /// Başlıklar + (HEAD değilse) gövde. Her yanıt `no-store`, `nosniff`, CSP taşır; CORS başlığı HİÇ eklenmez.
        func serialized() -> Data {
            var head = "HTTP/1.1 \(status) \(AgentWebRouter.reason(status))\r\n"
            head += "Content-Type: \(contentType)\r\n"
            head += "Content-Length: \(body.count)\r\n"
            head += AgentWebRouter.commonHeaders
            head += "Connection: close\r\n\r\n"
            var data = Data(head.utf8)
            if !headOnly { data.append(body) }
            return data
        }
    }

    enum Result: Equatable, Sendable {
        case response(Response)
        /// `GET /v1/stream`: dinleyici bağlantıyı SSE'ye çevirir.
        case stream
    }

    /// Yönlendirmenin ihtiyaç duyduğu anlık bağlam.
    struct Context: Sendable {
        var token: String
        var port: UInt16
        var enabled: Bool
        var webRoot: URL?
        var officeRoot: URL?
        var stateJSON: Data
        var layoutJSON: Data?
        var sseClients: Int
        var maxSSEClients = AgentWebRouter.maxSSEClients
    }

    static var commonHeaders: String {
        "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n"
            + "Cross-Origin-Resource-Policy: same-origin\r\nContent-Security-Policy: \(contentSecurityPolicy)\r\n"
    }

    static func reason(_ code: Int) -> String {
        switch code {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 421: "Misdirected Request"
        case 431: "Request Header Fields Too Large"
        case 503: "Service Unavailable"
        default: "Error"
        }
    }

    // MARK: Ayrıştırma

    /// Arabellek GET/HEAD isteği mi? (Diğer yöntemler eski ayrıştırıcıya gider.)
    static func isWebRequest(_ buffer: Data) -> Bool {
        buffer.starts(with: Data("GET ".utf8)) || buffer.starts(with: Data("HEAD ".utf8))
    }

    static func parse(_ buffer: Data) -> ParseOutcome {
        let terminator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: terminator) else {
            return buffer.count > AgentHTTPParser.maxHeader ? .reject(431) : .needMore
        }
        guard headerEnd.lowerBound <= AgentHTTPParser.maxHeader else { return .reject(431) }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .reject(400) }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .reject(400) }
        let method = String(requestLine[0])
        guard method == "GET" || method == "HEAD" else { return .reject(405) }
        let target = String(requestLine[1])
        guard target.hasPrefix("/"), !target.hasPrefix("//"), target.utf8.count <= maxTarget,
              !target.contains("#"), target.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else { return .reject(400) }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .reject(400) }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[key] != nil, ["host", "origin", AgentHTTPParser.tokenHeader, "content-length"].contains(key) { return .reject(400) }
            headers[key] = value
        }
        guard headers["transfer-encoding"] == nil else { return .reject(400) }
        if let length = headers["content-length"], length != "0" { return .reject(400) } // GET/HEAD gövdesiz
        return .request(Request(method: method, target: target, headers: headers))
    }

    // MARK: Yönlendirme

    static func route(_ request: Request, context: Context) -> Result {
        guard request.method == "GET" || request.method == "HEAD" else { return .response(error(405, request)) }
        guard context.enabled else { return .response(error(404, request)) }

        // DNS rebinding: yalnızca bu dinleyicinin kendi adresleri.
        let allowedHosts = ["127.0.0.1:\(context.port)", "localhost:\(context.port)"]
        guard let host = request.headers["host"]?.lowercased(), allowedHosts.contains(host) else { return .response(error(421, request)) }
        // Origin varsa aynı origin olmalı (CORS açılmaz; "null" da reddedilir).
        if let origin = request.headers["origin"], origin.lowercased() != "http://\(host)" { return .response(error(403, request)) }
        // Üst düzey gezinme (adres çubuğu, uzantı/Ayarlar'dan açma) `cross-site` görünebilir; erişim zaten token ile korunuyor.
        // Alt kaynak istekleri (fetch/img/script) çapraz site ise reddedilir.
        if let site = request.headers["sec-fetch-site"]?.lowercased(), site == "cross-site",
           request.headers["sec-fetch-mode"]?.lowercased() != "navigate" { return .response(error(403, request)) }

        guard !context.token.isEmpty, let provided = providedToken(request),
              AgentHTTPParser.constantTimeEqual(provided, context.token) else { return .response(error(401, request)) }

        let head = request.method == "HEAD"
        func ok(_ type: String, _ body: Data) -> Result { .response(Response(status: 200, contentType: type, body: body, headOnly: head)) }

        switch request.path {
        case "/", "/index.html":
            guard let root = context.webRoot, let page = readStatic(root, "index.html") else { return .response(error(404, request)) }
            let html = String(decoding: page, as: UTF8.self).replacingOccurrences(of: tokenPlaceholder, with: urlSafe(context.token))
            return ok("text/html; charset=utf-8", Data(html.utf8))
        case "/app.js":
            guard let root = context.webRoot, let data = readStatic(root, "app.js") else { return .response(error(404, request)) }
            return ok("text/javascript; charset=utf-8", data)
        case "/style.css":
            guard let root = context.webRoot, let data = readStatic(root, "style.css") else { return .response(error(404, request)) }
            return ok("text/css; charset=utf-8", data)
        case "/v1/state":
            return ok("application/json; charset=utf-8", context.stateJSON)
        case "/v1/layout":
            guard let layout = context.layoutJSON else { return .response(error(404, request)) }
            return ok("application/json; charset=utf-8", layout)
        case "/v1/stream":
            if head { return .response(error(405, request)) }
            return context.sseClients >= context.maxSSEClients ? .response(error(503, request)) : .stream
        default:
            if request.path.hasPrefix("/assets/") {
                let relative = String(request.path.dropFirst("/assets/".count))
                guard let root = context.officeRoot, let (data, type) = readAsset(relative, root: root) else { return .response(error(404, request)) }
                return ok(type, data)
            }
            return .response(error(404, request))
        }
    }

    private static func error(_ status: Int, _ request: Request) -> Response {
        Response(status: status, contentType: "text/plain; charset=utf-8", body: Data("\(status) \(reason(status))\n".utf8), headOnly: request.method == "HEAD")
    }

    /// Başlıktaki ya da `?t=` sorgusundaki token (yoksa nil).
    static func providedToken(_ request: Request) -> String? {
        if let header = request.headers[AgentHTTPParser.tokenHeader] { return header }
        guard let query = request.query else { return nil }
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if kv.count == 2, kv[0] == "t" { return String(kv[1]).removingPercentEncoding }
        }
        return nil
    }

    private static func urlSafe(_ token: String) -> String {
        token.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? ""
    }

    // MARK: Dosyalar

    static let assetDirectories: Set<String> = ["characters", "furniture", "floors", "walls", "carpets"]
    static let assetTypes: [String: String] = ["png": "image/png", "json": "application/json; charset=utf-8"]
    static let maxAssetBytes = 2 * 1024 * 1024
    private static let segmentCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")

    /// Sayfa dosyaları: sabit ad listesi (kullanıcı girdisi dosya adı olmaz), normal dosya, sembolik bağ değil.
    private static func readStatic(_ root: URL, _ name: String) -> Data? {
        guard let url = safeURL(root: root, components: [name]) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// `/assets/` sonrası göreli yol → izinli dosya. Yüzde-kodlama, `..`, `.`/gizli bölüm, ters eğik çizgi, izinsiz dizin/uzantı,
    /// sembolik bağ ve kök dışına çıkış → nil.
    static func resolveAsset(_ relative: String, root: URL) -> (url: URL, contentType: String)? {
        guard !relative.isEmpty, relative.utf8.count <= 200, !relative.contains("%"), !relative.contains("\\") else { return nil }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts.count <= 4, assetDirectories.contains(parts[0]) else { return nil }
        for part in parts {
            guard !part.isEmpty, !part.hasPrefix("."), !part.contains(".."),
                  part.unicodeScalars.allSatisfy({ segmentCharacters.contains($0) }) else { return nil }
        }
        guard let ext = parts.last?.split(separator: ".").last.map({ $0.lowercased() }), parts.last?.contains(".") == true,
              let type = assetTypes[ext] else { return nil }
        guard let url = safeURL(root: root, components: parts) else { return nil }
        return (url, type)
    }

    private static func readAsset(_ relative: String, root: URL) -> (Data, String)? {
        guard let (url, type) = resolveAsset(relative, root: root),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size <= maxAssetBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return (data, type)
    }

    /// `root` altında, hiçbir bileşeni sembolik bağ olmayan, normal bir dosya; kökten çıkamaz.
    static func safeURL(root: URL, components: [String]) -> URL? {
        let realRoot = root.resolvingSymlinksInPath().standardizedFileURL
        var current = realRoot
        let fm = FileManager.default
        for (i, name) in components.enumerated() {
            current = current.appending(path: name, directoryHint: i == components.count - 1 ? .notDirectory : .isDirectory)
            guard let type = (try? fm.attributesOfItem(atPath: current.path))?[.type] as? FileAttributeType else { return nil }
            if type == .typeSymbolicLink { return nil }
            if i == components.count - 1 { guard type == .typeRegular else { return nil } } else { guard type == .typeDirectory else { return nil } }
        }
        let path = current.standardizedFileURL.path
        guard path.hasPrefix(realRoot.path + "/") else { return nil }
        return current
    }

    // MARK: SSE çerçeveleme

    static let sseHeaders = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\n" + commonHeaders + "Connection: close\r\n\r\n"
    static let sseKeepAlive = Data(": keep-alive\n\n".utf8)

    /// `retry:` + `data: <tek satır JSON>\n\n`. JSON'daki satır sonu olmamalı (JSONSerialization sıkıştırılmış üretir); yine de savunma.
    static func sseEvent(_ json: Data) -> Data {
        var out = Data("data: ".utf8)
        out.append(Data(json.filter { $0 != 0x0A && $0 != 0x0D }))
        out.append(Data("\n\n".utf8))
        return out
    }

    static func sseOpening(_ json: Data) -> Data {
        var out = Data(sseHeaders.utf8)
        out.append(Data("retry: 3000\n\n".utf8))
        out.append(sseEvent(json))
        return out
    }
}

/// Dinleyici ile ana aktör arasındaki iş parçacığı güvenli köprü: anlık durum JSON'u, düzen JSON'u ve özellik bayrağı.
final class AgentWebStore: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var state = Data(#"{"v":1,"rooms":[]}"#.utf8)
    private var layout: Data?
    let webRoot: URL?
    let officeRoot: URL?

    init(webRoot: URL? = AgentWebStore.bundleWebRoot(), officeRoot: URL? = AgentWebStore.bundleOfficeRoot()) {
        self.webRoot = webRoot
        self.officeRoot = officeRoot
    }

    static func bundleOfficeRoot() -> URL? {
        Bundle.main.url(forResource: "Office", withExtension: nil) ?? Bundle(for: AgentWebStoreMarker.self).url(forResource: "Office", withExtension: nil)
    }

    static func bundleWebRoot() -> URL? {
        Bundle.main.url(forResource: "Web", withExtension: nil) ?? Bundle(for: AgentWebStoreMarker.self).url(forResource: "Web", withExtension: nil)
    }

    var isEnabled: Bool { lock.lock(); defer { lock.unlock() }; return enabled }
    func setEnabled(_ on: Bool) { lock.lock(); enabled = on; lock.unlock() }
    var stateJSON: Data { lock.lock(); defer { lock.unlock() }; return state }
    func setState(_ data: Data) { lock.lock(); state = data; lock.unlock() }
    func setLayout(_ data: Data?) { lock.lock(); layout = data; lock.unlock() }

    func context(token: String, port: UInt16, sseClients: Int) -> AgentWebRouter.Context {
        lock.lock(); defer { lock.unlock() }
        return AgentWebRouter.Context(token: token, port: port, enabled: enabled, webRoot: webRoot, officeRoot: officeRoot,
                                      stateJSON: state, layoutJSON: layout, sseClients: sseClients)
    }
}

private final class AgentWebStoreMarker {}
