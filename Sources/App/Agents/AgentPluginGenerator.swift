import CryptoKit
import Foundation

/// `~/Library/Application Support/Adalmon/ClaudePlugin/` altında yerel marketplace + plugin üretir.
/// Düzen: `.claude-plugin/marketplace.json`, `plugins/adalmon-agents/{.claude-plugin/plugin.json, hooks/hooks.json, scripts/*}`.
/// `config.json` (port + token, 0600) plugin dizininin DIŞINDA, marketplace kökündedir: Claude plugin'i kendi önbelleğine
/// kopyaladığı için betik yapılandırmayı sabit yoldan okur; port değişince yeniden kurulum gerekmez.
struct AgentPluginGenerator: Sendable {
    static let marketplaceName = "adalmon-local"
    static let pluginName = "adalmon-agents"
    static let pluginID = "adalmon-agents@adalmon-local"
    /// Betikler her değiştiğinde artırılır: Claude plugin'i kendi önbelleğine kopyalar ve yalnızca `version` değişince yeniler.
    /// `AgentPluginTests.testScriptDigestPinsVersion` betik özetini bu sürüme kilitler (sürümsüz betik değişikliği testi kırar).
    static let version = "1.3.0"
    /// Her iki betiğin birleşik SHA-256 özeti (ilk 16 hex); yalnızca sürüm kilidi testi içindir.
    static var scriptsDigest: String {
        let data = Data((AgentPluginScripts.python + "\n--\n" + AgentPluginScripts.shell).utf8)
        return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    static let hookEvents = AgentEvent.Name.allCases.map(\.rawValue)

    var root: URL
    /// Betiği çalıştıracak yorumlayıcı: /usr/bin/python3 varsa o, yoksa /bin/sh yedeği.
    var usesPython: Bool

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Adalmon/ClaudePlugin", directoryHint: .isDirectory)
    }

    /// python3 gerçekten çalışır mı: /usr/bin/python3 yalnızca Komut Satırı Araçları/Xcode yoksa kurulum penceresi açan bir saplamadır.
    static func pythonAvailable(fileManager: FileManager = .default) -> Bool {
        guard fileManager.isExecutableFile(atPath: "/usr/bin/python3") else { return false }
        return fileManager.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/python3")
            || fileManager.fileExists(atPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/python3")
            || fileManager.fileExists(atPath: "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework")
    }

    init(root: URL = Self.defaultRoot, usesPython: Bool = Self.pythonAvailable()) {
        self.root = root
        self.usesPython = usesPython
    }

    var pluginDirectory: URL { root.appending(path: "plugins/\(Self.pluginName)", directoryHint: .isDirectory) }
    var configURL: URL { root.appending(path: "config.json") }
    var marketplaceURL: URL { root.appending(path: ".claude-plugin/marketplace.json") }
    var manifestURL: URL { pluginDirectory.appending(path: ".claude-plugin/plugin.json") }
    var hooksURL: URL { pluginDirectory.appending(path: "hooks/hooks.json") }
    var pythonScriptURL: URL { pluginDirectory.appending(path: "scripts/forward.py") }
    var shellScriptURL: URL { pluginDirectory.appending(path: "scripts/forward.sh") }

    /// Hook komutu; `${CLAUDE_PLUGIN_ROOT}` Claude tarafından plugin köküne çözülür.
    var hookCommand: String {
        usesPython ? "/usr/bin/python3 \"${CLAUDE_PLUGIN_ROOT}/scripts/forward.py\"" : "/bin/sh \"${CLAUDE_PLUGIN_ROOT}/scripts/forward.sh\""
    }

    var marketplaceJSON: [String: Any] {
        [
            "name": Self.marketplaceName,
            "owner": ["name": "Adalmon"],
            "metadata": ["description": "Adalmon yerel marketplace'i"],
            "plugins": [[
                "name": Self.pluginName,
                "source": "./plugins/\(Self.pluginName)",
                "description": "Claude Code oturumlarını ve alt ajanlarını Adalmon'a (yalnızca bu Mac'e, 127.0.0.1) bildirir.",
                "version": Self.version,
            ] as [String: Any]],
        ]
    }

    var manifestJSON: [String: Any] {
        [
            "name": Self.pluginName,
            "version": Self.version,
            "description": "Adalmon: Claude Code oturum ve alt ajan durumunu yerel olarak izler. İstem, araç girdisi/çıktısı ve yanıt metni iletilmez.",
            "author": ["name": "Adalmon"],
        ]
    }

    var hooksJSON: [String: Any] {
        var hooks: [String: Any] = [:]
        for event in Self.hookEvents {
            hooks[event] = [["hooks": [["type": "command", "command": hookCommand, "async": true, "timeout": 5] as [String: Any]]]]
        }
        return ["hooks": hooks]
    }

    /// Tüm dosyaları yazar (var olanların üzerine). Betikler 0755, config 0600.
    func write(port: UInt16, token: String) throws {
        try writeJSON(marketplaceJSON, to: marketplaceURL)
        try writeJSON(manifestJSON, to: manifestURL)
        try writeJSON(hooksJSON, to: hooksURL)
        try writeText(AgentPluginScripts.python, to: pythonScriptURL, mode: 0o755)
        try writeText(AgentPluginScripts.shell, to: shellScriptURL, mode: 0o755)
        try writeConfig(port: port, token: token)
    }

    /// Yalnızca port/token yenilenir (betikler ve manifest dokunulmaz). `showTargets` verilirse o da yazılır; verilmezse var olan
    /// değer ve dosyadaki diğer anahtarlar korunur.
    func writeConfig(port: UInt16, token: String, showTargets: Bool? = nil) throws {
        var object = existingConfigObject()
        object["port"] = Int(port)
        object["token"] = token
        if let showTargets { object["showTargets"] = showTargets }
        try writeConfigObject(object)
    }

    /// Betikteki "Hedefi de göster" anahtarı (config.json `showTargets`); dosya yoksa/okunamazsa false.
    func readShowTargets() -> Bool { existingConfigObject()["showTargets"] as? Bool ?? false }

    /// Yalnızca `showTargets` yazılır (port/token ve mod korunur; dosya yoksa 0600 ile oluşturulur). Betik değişmez.
    func setShowTargets(_ on: Bool) throws {
        var object = existingConfigObject()
        object["showTargets"] = on
        try writeConfigObject(object)
    }

    private func existingConfigObject() -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private func writeConfigObject(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try ensureDirectory(root)
        let manager = FileManager.default
        // Önce 0600 ile boş dosya, sonra içerik: token hiçbir anda herkesçe okunabilir olmaz.
        if !manager.fileExists(atPath: configURL.path) {
            guard manager.createFile(atPath: configURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        try data.write(to: configURL)
    }

    func readConfig() -> (port: UInt16, token: String)? {
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = object["port"] as? Int, let value = UInt16(exactly: port), let token = object["token"] as? String, !token.isEmpty
        else { return nil }
        return (value, token)
    }

    /// Plugin dosyalarını siler (config dahil); marketplace kaydı `AgentPluginInstaller.uninstall` ile kaldırılır.
    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }

    /// 32 bayt rastgele, hex (64 karakter).
    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess { bytes = (0..<32).map { _ in UInt8.random(in: 0...255) } }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Dosya yardımcıları

    private func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: url)
    }

    private func writeText(_ text: String, to url: URL, mode: Int) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        try Data((text + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}
