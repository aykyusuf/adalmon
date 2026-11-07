import Foundation

/// Aynı görünen ada sahip satırları ayırt eden kısa yer ipucu ("Adalmon · DerivedData", "Adalmon · /Applications").
/// Saf mantık: ad çözümleme dışarıdan verilir. Ad benzersizse ipucu yoktur.
enum DuplicateNameHints {
    /// - Parameters:
    ///   - keys: listede görünen uygulama anahtarları.
    ///   - name: anahtar → görünen ad.
    ///   - home: kullanıcı klasörü (`~` kısaltması).
    /// - Returns: yalnızca adı çakışan anahtarlar için ipucu.
    static func hints(keys: [String], name: (String) -> String, home: String = NSHomeDirectory()) -> [String: String] {
        var byName: [String: [String]] = [:]
        for key in Set(keys) where !ResourceKeys.isSpecial(key) { byName[name(key), default: []].append(key) }
        var out: [String: String] = [:]
        for group in byName.values where group.count > 1 {
            let candidates: [[(key: String, label: String)]] = [
                group.map { ($0, shortLabel(for: $0, home: home)) },
                group.map { ($0, mediumLabel(for: $0, home: home)) },
                group.map { ($0, abbreviate(executablePath(of: $0), home: home)) },
            ]
            var resolved: [String: String] = [:]
            var pending = Set(group)
            for level in candidates {
                let counts = Dictionary(grouping: level.filter { pending.contains($0.key) }, by: \.label).mapValues(\.count)
                for item in level where pending.contains(item.key) && counts[item.label] == 1 {
                    resolved[item.key] = item.label
                    pending.remove(item.key)
                }
                if pending.isEmpty { break }
            }
            // Hâlâ çakışanlar (aynı yol, farklı terminal): tam anahtar.
            for key in pending { resolved[key] = abbreviate(key, home: home) }
            for (key, label) in resolved where !label.isEmpty { out[key] = label }
        }
        return out
    }

    /// Ad çözümlemesinde kullanılan yol: terminal alt anahtarında çocuğun çalıştırılabilir yolu.
    static func executablePath(of key: String) -> String {
        if let parts = TerminalChildKey.split(key), parts.child != TerminalChildKey.residual { return parts.child }
        if let parts = TerminalChildKey.split(key) { return parts.terminal }
        return key
    }

    /// Kısa, anlamlı etiket ("DerivedData", "/Applications", "Homebrew", …).
    static func shortLabel(for key: String, home: String) -> String {
        let dir = (executablePath(of: key) as NSString).deletingLastPathComponent
        if dir.contains("/DerivedData/") || dir.hasSuffix("/DerivedData") { return "DerivedData" }
        if dir.contains("/Xcode/Archives/") { return "Arşiv" }
        if dir.contains("/.Trash") { return "Çöp Kutusu" }
        if dir == "/Applications" { return "/Applications" }
        if dir == home + "/Applications" { return "~/Applications" }
        if dir.hasPrefix("/System/Applications") { return "Sistem" }
        if dir.hasPrefix("/opt/homebrew") { return "Homebrew" }
        if dir.hasPrefix("/Volumes/") {
            let parts = dir.split(separator: "/")
            if parts.count >= 2 { return String(parts[1]) }
        }
        if dir.hasPrefix("/private/tmp") || dir.hasPrefix("/tmp") || dir.hasPrefix("/private/var/folders") || dir.hasPrefix("/var/folders") {
            return "Geçici"
        }
        return abbreviate(dir, home: home)
    }

    /// İkinci aşama: aynı kısa etikette çakışanlar için daha özgül etiket (DerivedData'da proje klasörü; diğerlerinde tam klasör).
    static func mediumLabel(for key: String, home: String) -> String {
        let path = executablePath(of: key)
        let dir = (path as NSString).deletingLastPathComponent
        if let r = dir.range(of: "/DerivedData/") {
            let rest = dir[r.upperBound...]
            if let first = rest.split(separator: "/").first { return "DerivedData/" + first }
        }
        return abbreviate(dir, home: home)
    }

    static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
