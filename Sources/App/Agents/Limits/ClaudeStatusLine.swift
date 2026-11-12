import CryptoKit
import Foundation

// "Claude limitlerini bağla": ~/.claude/settings.json'daki statusLine komutunu Adalmon sarmalayıcısıyla değiştirir. Sarmalayıcı stdin'i
// bir kez okur, `rate_limits`'ten yalnızca dört sayıyı arka planda yerel dinleyiciye yollar, sonra kullanıcının ÖZGÜN komutunu aynı
// stdin ile çalıştırır ve çıktısını değiştirmeden geçirir. Bağlantı kaldırılınca settings.json eski haline döner.

/// settings.json üzerinde saf metin dönüşümü (JSON metni girer, JSON metni çıkar). Yalnızca üst düzey `statusLine` değerinin bayt
/// aralığı değişir; diğer anahtarlar, sıra, boşluklar ve biçim bayt bayt korunur. Bağla → kaldır, özgün metni birebir geri verir.
enum ClaudeStatusLineTransform {
    static let marker = "statusline-wrapper.sh"

    enum TransformError: Error, Equatable {
        /// Dosya geçerli bir JSON nesnesi değil (dokunulmaz).
        case invalidJSON
    }

    struct Connected: Equatable {
        var text: String
        /// Özgün `statusLine` değerinin ham JSON metni (yoksa nil). Kaldırırken aynen geri yazılır.
        var originalRaw: String?
        /// Zaten bizim sarmalayıcımıza bakıyordu: metin değişmedi, özgün değer bilinmiyor (eskisi korunmalı).
        var alreadyConnected: Bool
    }

    /// `statusLine.command` bizim sarmalayıcımız mı?
    static func isWrapper(_ statusLine: Any?) -> Bool {
        guard let object = statusLine as? [String: Any], let command = object["command"] as? String else { return false }
        return command.contains(marker)
    }

    static func connect(_ text: String?, wrapperCommand: String) throws -> Connected {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let value = try serialize(["type": "command", "command": wrapperCommand])
            return Connected(text: "{\n  \"statusLine\": \(value)\n}\n", originalRaw: nil, alreadyConnected: false)
        }
        let object = try parseObject(text)
        let current = object["statusLine"]
        if isWrapper(current) { return Connected(text: text, originalRaw: nil, alreadyConnected: true) }

        var replacement: [String: Any] = (current as? [String: Any]) ?? [:]
        replacement["type"] = "command"
        replacement["command"] = wrapperCommand
        let value = try serialize(replacement)

        let bytes = Array(text.utf8)
        let scan = try JSONSpanScanner.topLevel(bytes)
        if let member = scan.members.last(where: { $0.key == "statusLine" }) {
            let raw = String(decoding: bytes[member.value], as: UTF8.self)
            let out = Array(bytes[..<member.value.lowerBound]) + Array(value.utf8) + Array(bytes[member.value.upperBound...])
            return Connected(text: String(decoding: out, as: UTF8.self), originalRaw: raw, alreadyConnected: false)
        }
        let out: [UInt8]
        if let last = scan.members.last {
            let indent = scan.memberIndent(bytes) ?? "  "
            let insert = Array(",\n\(indent)\"statusLine\": \(value)".utf8)
            out = Array(bytes[..<last.value.upperBound]) + insert + Array(bytes[last.value.upperBound...])
        } else {
            let insert = Array("\n  \"statusLine\": \(value)\n".utf8)
            out = Array(bytes[...scan.open]) + insert + Array(bytes[scan.close...])
        }
        return Connected(text: String(decoding: out, as: UTF8.self), originalRaw: nil, alreadyConnected: false)
    }

    /// `statusLine` hâlâ sarmalayıcıya bakıyorsa özgün değeri geri koyar (özgün yoksa anahtarı siler). Kullanıcı bu arada başka bir
    /// statusLine yazdıysa dokunmaz ve nil döner.
    static func disconnect(_ text: String, originalRaw: String?) throws -> String? {
        let object = try parseObject(text)
        guard isWrapper(object["statusLine"]) else { return nil }
        let bytes = Array(text.utf8)
        let scan = try JSONSpanScanner.topLevel(bytes)
        guard let index = scan.members.lastIndex(where: { $0.key == "statusLine" }) else { return nil }
        let member = scan.members[index]
        let out: [UInt8]
        if let originalRaw {
            out = Array(bytes[..<member.value.lowerBound]) + Array(originalRaw.utf8) + Array(bytes[member.value.upperBound...])
        } else if index > 0 {
            // Önceki üyenin bitişinden bu değerin sonuna kadar (", \n  "statusLine": …") silinir: eklemenin tam tersi.
            out = Array(bytes[..<scan.members[index - 1].value.upperBound]) + Array(bytes[member.value.upperBound...])
        } else if scan.members.count > 1 {
            out = Array(bytes[..<member.keyStart]) + Array(bytes[scan.members[1].keyStart...])
        } else {
            out = Array(bytes[...scan.open]) + Array(bytes[scan.close...])
        }
        let result = String(decoding: out, as: UTF8.self)
        _ = try parseObject(result)
        return result
    }

    static func parseObject(_ text: String) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw TransformError.invalidJSON }
        return object
    }

    private static func serialize(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}

/// Geçerli olduğu bilinen bir JSON nesne metninde üst düzey üyelerin bayt aralıkları.
enum JSONSpanScanner {
    struct Member {
        var key: String
        var keyStart: Int
        var value: Range<Int>
    }

    struct Scan {
        var open: Int
        var close: Int
        var members: [Member]

        /// İlk üyenin satır başı girintisi (yalnızca boşluk/sekme ise).
        func memberIndent(_ bytes: [UInt8]) -> String? {
            guard let first = members.first else { return nil }
            var i = first.keyStart
            while i > 0, bytes[i - 1] == 0x20 || bytes[i - 1] == 0x09 { i -= 1 }
            guard i > 0, bytes[i - 1] == 0x0A else { return nil }
            return String(decoding: bytes[i..<first.keyStart], as: UTF8.self)
        }
    }

    static func topLevel(_ b: [UInt8]) throws -> Scan {
        var i = skip(b, 0)
        guard i < b.count, b[i] == UInt8(ascii: "{") else { throw ClaudeStatusLineTransform.TransformError.invalidJSON }
        let open = i
        i += 1
        var members: [Member] = []
        while true {
            i = skip(b, i)
            guard i < b.count else { throw ClaudeStatusLineTransform.TransformError.invalidJSON }
            if b[i] == UInt8(ascii: "}") { return Scan(open: open, close: i, members: members) }
            if b[i] == UInt8(ascii: ",") { i += 1; continue }
            guard b[i] == UInt8(ascii: "\"") else { throw ClaudeStatusLineTransform.TransformError.invalidJSON }
            let keyStart = i
            let keyEnd = try stringEnd(b, i)
            let keyData = Data(b[keyStart..<keyEnd])
            let key = (try? JSONSerialization.jsonObject(with: keyData, options: .fragmentsAllowed)) as? String ?? ""
            i = skip(b, keyEnd)
            guard i < b.count, b[i] == UInt8(ascii: ":") else { throw ClaudeStatusLineTransform.TransformError.invalidJSON }
            i = skip(b, i + 1)
            let valueEnd = try valueEnd(b, i)
            members.append(Member(key: key, keyStart: keyStart, value: i..<valueEnd))
            i = valueEnd
        }
    }

    private static func skip(_ b: [UInt8], _ start: Int) -> Int {
        var i = start
        while i < b.count, [0x20, 0x09, 0x0A, 0x0D].contains(b[i]) { i += 1 }
        return i
    }

    /// `start` bir çift tırnaktır; kapanan tırnağın bir sonrasını döner.
    private static func stringEnd(_ b: [UInt8], _ start: Int) throws -> Int {
        var i = start + 1
        while i < b.count {
            if b[i] == UInt8(ascii: "\\") { i += 2; continue }
            if b[i] == UInt8(ascii: "\"") { return i + 1 }
            i += 1
        }
        throw ClaudeStatusLineTransform.TransformError.invalidJSON
    }

    private static func valueEnd(_ b: [UInt8], _ start: Int) throws -> Int {
        guard start < b.count else { throw ClaudeStatusLineTransform.TransformError.invalidJSON }
        switch b[start] {
        case UInt8(ascii: "\""):
            return try stringEnd(b, start)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0, i = start
            while i < b.count {
                switch b[i] {
                case UInt8(ascii: "\""): i = try stringEnd(b, i); continue
                case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { return i + 1 }
                default: break
                }
                i += 1
            }
            throw ClaudeStatusLineTransform.TransformError.invalidJSON
        default:
            var i = start
            while i < b.count, ![UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x09, 0x0A, 0x0D].contains(b[i]) { i += 1 }
            return i
        }
    }
}

/// Sarmalayıcı betiğinin üretimi (saf). Özgün komut tek tırnak içinde gömülür (`'` → `'\''`); çok satırlı komutlar aynen korunur.
enum ClaudeStatusLineWrapper {
    static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// settings.json'a yazılan komut.
    static func command(scriptPath: String) -> String { "/bin/sh \(shellQuote(scriptPath))" }

    /// `originalCommand` nil ise sarmalayıcı hiçbir şey yazdırmaz (yalnızca limitleri iletir).
    static func script(originalCommand: String?, configPath: String) -> String {
        let run: String = if let originalCommand {
            """
            ADALMON_SL_ORIGINAL=\(shellQuote(originalCommand))
            printf '%s' "$ADALMON_SL_INPUT" | /bin/sh -c "$ADALMON_SL_ORIGINAL"
            exit $?
            """
        } else {
            "exit 0"
        }
        return """
        #!/bin/sh
        # Adalmon statusLine sarmalayıcısı (Ayarlar › Claude ajanları › Abonelik limitleri ile kuruldu; elle düzenlemeyin).
        # 1) stdin'i bir kez okur. 2) Arka planda rate_limits'ten yalnızca dört sayıyı (5 saat / 7 gün: kullanılan yüzde ve yenilenme
        #    anı) 127.0.0.1'deki Adalmon dinleyicisine yollar; durum satırını geciktirmez, hata olursa sessizdir.
        # 3) Özgün statusLine komutunu aynı stdin ile çalıştırır; çıktısı ve çıkış kodu değiştirilmeden geçer.
        ADALMON_SL_DEFAULT_CONFIG=\(shellQuote(configPath))
        ADALMON_SL_CONFIG="${ADALMON_AGENTS_CONFIG:-$ADALMON_SL_DEFAULT_CONFIG}"
        ADALMON_SL_INPUT=$(/bin/cat; printf x)
        ADALMON_SL_INPUT=${ADALMON_SL_INPUT%x}
        if [ -n "$ADALMON_SL_WRAPPED" ]; then exit 0; fi
        export ADALMON_SL_WRAPPED=1
        (
          get() { printf '%s' "$ADALMON_SL_INPUT" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null; }
          BODY=""
          SEP=""
          add() {
            V=$(get "$2")
            case "$V" in ''|*[!0-9.eE+-]*) return 0 ;; esac
            BODY="$BODY$SEP\\"$1\\":$V"
            SEP=","
          }
          add five_hour_used rate_limits.five_hour.used_percentage
          add five_hour_resets_at rate_limits.five_hour.resets_at
          add seven_day_used rate_limits.seven_day.used_percentage
          add seven_day_resets_at rate_limits.seven_day.resets_at
          [ -n "$BODY" ] || exit 0
          PORT=$(/usr/bin/plutil -extract port raw -o - "$ADALMON_SL_CONFIG" 2>/dev/null)
          TOKEN=$(/usr/bin/plutil -extract token raw -o - "$ADALMON_SL_CONFIG" 2>/dev/null)
          case "$PORT" in ''|*[!0-9]*) exit 0 ;; esac
          case "$TOKEN" in ''|*[!A-Za-z0-9]*) exit 0 ;; esac
          ESCAPED=$(printf '%s' "{$BODY}" | /usr/bin/sed 's/"/\\\\"/g')
          # Token komut satırında görünmesin diye curl yapılandırması stdin'den okunur.
          printf 'url = "http://127.0.0.1:%s/v1/limits"\\nheader = "X-Adalmon-Token: %s"\\nheader = "Content-Type: application/json"\\ndata-binary = "%s"\\n' \\
            "$PORT" "$TOKEN" "$ESCAPED" | /usr/bin/curl -s -o /dev/null --max-time 2 -K - >/dev/null 2>&1
        ) </dev/null >/dev/null 2>&1 &
        \(run)
        """ + "\n"
    }
}

/// Dosya işlemleri: yedek, sarmalayıcı, durum dosyası, settings.json yazımı. Yollar enjekte edilir (testler geçici dizin kullanır).
/// Sarmalayıcı `Adalmon/ClaudeStatusLine/` altındadır: ajan plugin'ini kaldırmak `ClaudePlugin/` klasörünü sildiği için orada dursa
/// durum satırı bozulurdu.
struct ClaudeStatusLineBinder: Sendable {
    struct State: Codable, Equatable {
        /// Özgün statusLine değerinin ham JSON metni (yoksa nil).
        var originalRaw: String?
        /// Bağlarken yazılan settings.json'un SHA-256'sı: dosya o zamandan beri değişmediyse yedek birebir geri yazılır.
        var writtenSHA256: String
        var backupPath: String?
        var connectedAt: Date
    }

    enum BinderError: Error, Equatable, LocalizedError {
        /// settings.json var ama okunamadı ya da UTF-8 değil: dosyaya dokunulmaz.
        case unreadableSettings
        /// settings.json okuma ile yazma arasında değişti: yazılmadı.
        case settingsChanged

        var errorDescription: String? {
            switch self {
            case .unreadableSettings: "~/.claude/settings.json okunamadı (izin ya da UTF-8 olmayan içerik); dosyaya dokunulmadı."
            case .settingsChanged: "~/.claude/settings.json bu sırada değişti; hiçbir şey yazılmadı, yeniden deneyin."
            }
        }
    }

    enum Outcome: Equatable {
        case connected(backup: URL?)
        case alreadyConnected
        case disconnected
        /// statusLine bu arada başka bir şeye çevrilmiş: settings.json'a dokunulmadı.
        case notOurs
        case notConnected
    }

    var settingsURL: URL
    /// `~/Library/Application Support/Adalmon`
    var supportDirectory: URL
    /// Sarmalayıcının port/token okuyacağı config.json (ajan plugin'iyle aynı dosya).
    var configURL: URL

    static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")
    }

    static var defaultSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Adalmon", directoryHint: .isDirectory)
    }

    init(settingsURL: URL = Self.defaultSettingsURL, supportDirectory: URL = Self.defaultSupportDirectory,
         configURL: URL = AgentPluginGenerator.defaultRoot.appending(path: "config.json")) {
        self.settingsURL = settingsURL
        self.supportDirectory = supportDirectory
        self.configURL = configURL
    }

    var directory: URL { supportDirectory.appending(path: "ClaudeStatusLine", directoryHint: .isDirectory) }
    var wrapperURL: URL { directory.appending(path: ClaudeStatusLineTransform.marker) }
    var stateURL: URL { directory.appending(path: "state.json") }
    var backupDirectory: URL { supportDirectory.appending(path: "Backups", directoryHint: .isDirectory) }
    var wrapperCommand: String { ClaudeStatusLineWrapper.command(scriptPath: wrapperURL.path) }

    func readState() -> State? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(State.self, from: data)
    }

    var isConnected: Bool {
        guard readState() != nil, let text = try? readSettings(),
              let object = try? ClaudeStatusLineTransform.parseObject(text) else { return false }
        return ClaudeStatusLineTransform.isWrapper(object["statusLine"])
    }

    /// Özgün komut (yalnızca `type: command` ise); yoksa nil.
    static func originalCommand(fromRaw raw: String?) -> String? {
        guard let raw, let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let command = object["command"] as? String, !command.isEmpty, !command.contains(ClaudeStatusLineTransform.marker) else { return nil }
        return command
    }

    func connect(now: Date = .now) throws -> Outcome {
        let original = try readSettings()
        let result = try ClaudeStatusLineTransform.connect(original, wrapperCommand: wrapperCommand)
        if result.alreadyConnected {
            // Özgün değer yalnızca durum dosyasında: asla üzerine yazılmaz. Sarmalayıcı eksikse yeniden üretilir.
            if let state = readState() {
                try writeWrapper(originalRaw: state.originalRaw)
            } else {
                // Durum dosyası yok (destek klasörü silinmiş) ama settings.json bizim sarmalayıcıya bakıyor: özgün komut bilinmez,
                // geçiş yapan (hiçbir şey yazdırmayan) sarmalayıcı + durum yazılır; böylece çalışır ve kaldırılabilir.
                try writeWrapper(originalRaw: nil)
                try writeState(State(originalRaw: nil, writtenSHA256: Self.sha256(original ?? ""), backupPath: nil, connectedAt: now))
            }
            return .alreadyConnected
        }
        var backup: URL?
        if let original {
            let name = "claude-settings-\(Self.stamp(now)).json"
            let url = backupDirectory.appending(path: name)
            let manager = FileManager.default
            try manager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            guard !manager.fileExists(atPath: url.path),
                  manager.createFile(atPath: url.path, contents: Data(original.utf8), attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteFileExists)
            }
            backup = url
            pruneBackups(keeping: url)
        }
        // Önce sarmalayıcı, sonra settings.json: statusLine hiçbir an olmayan bir dosyaya bakmaz.
        try writeWrapper(originalRaw: result.originalRaw)
        try writeState(State(originalRaw: result.originalRaw, writtenSHA256: Self.sha256(result.text), backupPath: backup?.path, connectedAt: now))
        try writeSettings(result.text, replacing: original)
        return .connected(backup: backup)
    }

    func disconnect() throws -> Outcome {
        guard let state = readState() else { return .notConnected }
        // Okuma/çözme hatası fırlatır (durum dosyası silinmez); yalnızca "dosya yok" bağlantısız sayılır.
        guard let text = try readSettings() else {
            try? FileManager.default.removeItem(at: stateURL)
            return .notConnected
        }
        if Self.sha256(text) == state.writtenSHA256, let path = state.backupPath,
           let backup = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) {
            try writeSettings(backup, replacing: text)
        } else if let restored = try ClaudeStatusLineTransform.disconnect(text, originalRaw: state.originalRaw) {
            try writeSettings(restored, replacing: text)
        } else {
            try? FileManager.default.removeItem(at: stateURL)
            return .notOurs
        }
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: wrapperURL)
        return .disconnected
    }

    /// Bağlıyken sarmalayıcı dosyası silinmişse durumdan yeniden üretir (durum satırı boş kalmasın).
    func repairWrapperIfNeeded() {
        guard !FileManager.default.fileExists(atPath: wrapperURL.path), let state = readState(), isConnected else { return }
        try? writeWrapper(originalRaw: state.originalRaw)
    }

    // MARK: Yardımcılar

    /// nil yalnızca dosya YOKSA. Başka her okuma/çözme hatası fırlatır (üzerine yazılmasın).
    func readSettings() throws -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: settingsURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        } catch {
            throw BinderError.unreadableSettings
        }
        guard let text = String(data: data, encoding: .utf8) else { throw BinderError.unreadableSettings }
        return text
    }

    /// Yalnızca en yeni 10 yedek kalır (`keeping` her zaman korunur).
    private func pruneBackups(keeping: URL, limit: Int = 10) {
        let manager = FileManager.default
        let names = ((try? manager.contentsOfDirectory(atPath: backupDirectory.path)) ?? [])
            .filter { $0.hasPrefix("claude-settings-") && $0.hasSuffix(".json") }
            .sorted(by: >)
        for name in names.dropFirst(limit) where name != keeping.lastPathComponent {
            try? manager.removeItem(at: backupDirectory.appending(path: name))
        }
    }

    private func writeWrapper(originalRaw: String?) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = ClaudeStatusLineWrapper.script(originalCommand: Self.originalCommand(fromRaw: originalRaw), configPath: configURL.path)
        try Data(script.utf8).write(to: wrapperURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapperURL.path)
    }

    private func writeState(_ state: State) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    /// Sembolik bağlantı varsa hedefine yazar (dotfiles düzeni bozulmasın); var olan izinler korunur.
    /// `previous`: okunduğu andaki içerik (nil = dosya yoktu). Yazmadan hemen önce yeniden okunur; değiştiyse yazılmaz.
    func writeSettings(_ text: String, replacing previous: String?) throws {
        guard try readSettings().map(Self.sha256) == previous.map(Self.sha256) else { throw BinderError.settingsChanged }
        let target = settingsURL.resolvingSymlinksInPath()
        let manager = FileManager.default
        let permissions = (try? manager.attributesOfItem(atPath: target.path))?[.posixPermissions]
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target, options: .atomic)
        if let permissions { try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: date)
    }
}
