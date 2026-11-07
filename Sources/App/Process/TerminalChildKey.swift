import Foundation

/// Terminal alt süreç anahtarı: `"<terminal .app yolu>|<çalıştırılabilir yol>"`. Kalan (kısa ömürlü süreçler) için
/// çalıştırılabilir yol yerine `residual` kullanılır. Anahtar SQLite `proc_app` tablosunda olduğu gibi saklanır.
enum TerminalChildKey {
    static let separator: Character = "|"
    static let residual = "__residual__"
    static let residualLabel = "diğer (kısa ömürlü süreçler)"
    static let arrow = " › "

    static func make(terminal: String, child: String) -> String { "\(terminal)\(separator)\(child)" }

    static func residualKey(terminal: String) -> String { make(terminal: terminal, child: residual) }

    /// Yol ile başlayan ve ayırıcı içeren anahtarlar terminal alt anahtarıdır.
    static func isChild(_ key: String) -> Bool { split(key) != nil }

    static func split(_ key: String) -> (terminal: String, child: String)? {
        guard key.hasPrefix("/"), let i = key.firstIndex(of: separator) else { return nil }
        let terminal = String(key[..<i])
        let child = String(key[key.index(after: i)...])
        return terminal.isEmpty || child.isEmpty ? nil : (terminal, child)
    }

    static func isResidual(_ key: String) -> Bool { split(key)?.child == residual }

    /// "Warp › xcodebuild". `appName`: terminal uygulama anahtarının görünen adı.
    static func displayName(_ key: String, appName: (String) -> String) -> String? {
        guard let parts = split(key) else { return nil }
        let child = parts.child == residual ? residualLabel : AppNaming.executableName(parts.child)
        return appName(parts.terminal) + arrow + child
    }
}
