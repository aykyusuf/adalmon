import Foundation

/// "Chrome sekme RAM'i (gelişmiş)": ayrı profille, yalnızca 127.0.0.1'e açılan hata ayıklama portuyla başlatılan Chrome.
/// Chrome 136+ varsayılan profilde `--remote-debugging-port`'u yok sayar; bu yüzden AYRI `--user-data-dir` şarttır.
/// Bu dosyadaki her şey saftır (testlerde gerçek Chrome / ağ çağrısı yok).
enum ChromeDebugConfig {
    static let bundleID = "com.google.Chrome"
    /// Kullanıcının asıl profili DEĞİL: oturumlar / şifreler taşınmaz.
    static let profileFolderName = "ChromeDebug"
    /// Dinamik (geçici) port aralığı.
    static let portRange: ClosedRange<Int> = 49_152...65_535

    /// `~/Library/Application Support/Adalmon/ChromeDebug` (boşluklu yol; kabuktan geçmez, argüman dizisi olarak verilir).
    static func userDataDirectory(applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent("Adalmon", isDirectory: true)
            .appendingPathComponent(profileFolderName, isDirectory: true)
    }

    /// `/usr/bin/open` argümanları: `-n` yeni örnek (açık olan Chrome kapatılmaz), `-a <Chrome.app>`, `--args` sonrası Chrome bayrakları.
    static func openArguments(appPath: String, port: Int, userDataDir: String) -> [String] {
        ["-n", "-a", appPath, "--args",
         "--remote-debugging-port=\(port)",
         "--remote-debugging-address=127.0.0.1",
         "--user-data-dir=\(userDataDir)",
         "--no-first-run",
         "--no-default-browser-check"]
    }
}

/// Rastgele boş port seçimi (saf: rastgelelik ve "boş mu" denetimi enjekte edilir).
enum DebugPortPicker {
    static func pick(range: ClosedRange<Int> = ChromeDebugConfig.portRange, attempts: Int = 32,
                     random: (ClosedRange<Int>) -> Int = { Int.random(in: $0) }, isFree: (Int) -> Bool) -> Int? {
        for _ in 0..<max(0, attempts) {
            let port = random(range)
            guard range.contains(port) else { continue }
            if isFree(port) { return port }
        }
        return nil
    }
}

/// Chrome'un `--user-data-dir` içine yazdığı `DevToolsActivePort` dosyası: 1. satır port, 2. satır tarayıcı ws yolu.
/// Aynı profil zaten açıksa ikinci `open -n` mevcut örneğe devreder ve yeni portu yok sayar; gerçek port buradan okunur.
enum DevToolsActivePort {
    static let fileName = "DevToolsActivePort"

    static func parse(_ text: String) -> Int? {
        guard let first = text.split(whereSeparator: \.isNewline).first,
              let port = Int(first.trimmingCharacters(in: .whitespaces)), (1...65_535).contains(port) else { return nil }
        return port
    }
}

/// Uç nokta güvenliği: yalnızca 127.0.0.1 / localhost ve beklenen port. `webSocketDebuggerUrl` körü körüne izlenmez.
enum CDPEndpointGuard {
    static func isAllowed(_ url: URL, port: Int, schemes: Set<String> = ["ws"]) -> Bool {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
              let host = url.host?.lowercased(), host == "127.0.0.1" || host == "localhost",
              url.port == port else { return false }
        return true
    }

    static func httpURL(port: Int, path: String) -> URL? {
        URL(string: "http://127.0.0.1:\(port)\(path)")
    }
}

/// `/json/list` öğesi.
struct CDPTarget: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var type: String
    var title: String
    var url: String
    var webSocketDebuggerUrl: String?
}

/// `/json/version` (yalnızca tarayıcı ws adresi kullanılır).
struct CDPVersion: Decodable, Equatable, Sendable {
    var browser: String?
    var webSocketDebuggerUrl: String?

    enum CodingKeys: String, CodingKey {
        case browser = "Browser"
        case webSocketDebuggerUrl
    }
}

/// Sekme başına `Performance.getMetrics` değerleri ("JS belleği"; süreç RAM'i DEĞİL). Eksik metrik nil.
struct CDPTabMetrics: Equatable, Sendable {
    var jsHeapUsed: Double?
    var jsHeapTotal: Double?
    var nodes: Double?
    var documents: Double?
}

/// `SystemInfo.getProcessInfo` öğesi (deneysel alan; en iyi çaba).
struct CDPProcess: Equatable, Sendable {
    var type: String
    var id: Int32
    var cpuTime: Double
}

/// Bir CDP yanıtı: `id` eşleşen sonuç ya da hata. Olaylar (`id` yok) nil döner.
struct CDPReply: Sendable {
    var id: Int
    /// `result` nesnesinin JSON'u (hata varsa nil).
    var result: Data?
    var errorMessage: String?
}

/// CDP mesaj kodlama / ayrıştırma.
enum CDPCodec {
    static func targets(from data: Data) throws -> [CDPTarget] {
        try JSONDecoder().decode([CDPTarget].self, from: data).filter { $0.type == "page" }
    }

    static func version(from data: Data) throws -> CDPVersion {
        try JSONDecoder().decode(CDPVersion.self, from: data)
    }

    static func request(id: Int, method: String, params: [String: String] = [:]) -> Data {
        let object: [String: Any] = ["id": id, "method": method, "params": params]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    static func reply(from data: Data) -> CDPReply? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? Int else { return nil }
        if let error = object["error"] as? [String: Any] {
            return CDPReply(id: id, result: nil, errorMessage: (error["message"] as? String) ?? "CDP hatası")
        }
        let result = (object["result"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data("{}".utf8)
        return CDPReply(id: id, result: result, errorMessage: nil)
    }

    /// `{"metrics":[{"name":"JSHeapUsedSize","value":…},…]}`; adlar şemada yok, ada göre aranır.
    static func metrics(from result: Data) -> CDPTabMetrics? {
        guard let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any],
              let list = object["metrics"] as? [[String: Any]] else { return nil }
        var values: [String: Double] = [:]
        for item in list {
            guard let name = item["name"] as? String, let value = (item["value"] as? NSNumber)?.doubleValue else { continue }
            values[name] = value
        }
        return CDPTabMetrics(jsHeapUsed: values["JSHeapUsedSize"], jsHeapTotal: values["JSHeapTotalSize"],
                             nodes: values["Nodes"], documents: values["Documents"])
    }

    /// `{"processInfo":[{"type":"renderer","id":123,"cpuTime":1.5},…]}`.
    static func processes(from result: Data) -> [CDPProcess]? {
        guard let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any],
              let list = object["processInfo"] as? [[String: Any]] else { return nil }
        return list.compactMap { item in
            guard let type = item["type"] as? String, let id = (item["id"] as? NSNumber)?.int32Value, id > 0 else { return nil }
            return CDPProcess(type: type, id: id, cpuTime: (item["cpuTime"] as? NSNumber)?.doubleValue ?? 0)
        }
    }
}

/// Chrome hata ayıklama örneğinin renderer RAM'i: `SystemInfo.getProcessInfo` pid'leri, yolu Chrome'a ait olanlarla
/// sınırlanarak (pid deneysel alandır; yanlış eşleşmeye karşı yol denetimi) ayak izleri toplanır.
struct ChromeRendererMemory: Equatable, Sendable {
    var count: Int
    var total: UInt64

    static func make(processes: [CDPProcess], path: (Int32) -> String?, footprint: (Int32) -> UInt64?) -> ChromeRendererMemory {
        var count = 0
        var total: UInt64 = 0
        for p in processes where p.type == "renderer" {
            guard let exe = path(p.id), exe.contains("Google Chrome"), let bytes = footprint(p.id) else { continue }
            count += 1
            total &+= bytes
        }
        return ChromeRendererMemory(count: count, total: total)
    }
}
