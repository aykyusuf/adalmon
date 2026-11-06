import Foundation

/// Uygulama anahtarı → insan dostu ad/tür. Saf mantık (AppKit yok), bu yüzden test edilebilir.
/// Anahtarın kendisi (limit, engel, kural) değişmez; bu yalnızca gösterim katmanıdır.
enum AppNaming {
    static let webKitName = "Safari / WebKit"

    private static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/",
                                         "/Library/PrivilegedHelperTools/"]

    /// - Parameter bundleName: `.app` yolu için Info.plist'ten görünen ad (test için enjekte edilebilir).
    static func identity(forApp key: String, bundleName: (String) -> String? = { _ in nil }) -> AppIdentity {
        let path = outermostApp(of: key)
        let last = (path as NSString).lastPathComponent
        // Yalnızca .app/.xpc uzantısı atılır ("com.apple.Safari.SafeBrowsing.Service" gibi noktalı adlar bozulmasın).
        let stem = (last.hasSuffix(".app") || last.hasSuffix(".xpc")) ? (last as NSString).deletingPathExtension : last

        if path.hasSuffix(".app") {
            if let o = AppNameTable.appOverrides[stem.lowercased()] {
                return AppIdentity(name: o.name, kind: .application, iconBundleID: o.iconBundleID)
            }
            let raw = bundleName(path).map(cleaned).flatMap { $0.isEmpty ? nil : $0 } ?? stem
            return AppIdentity(name: stripHelperSuffix(raw), kind: .application, iconBundleID: nil)
        }
        if last.isEmpty { return AppIdentity(name: key, kind: .commandLineTool, iconBundleID: nil) }

        let lower = path.lowercased()
        if lower.contains("/.local/share/claude/") || lower.contains("/claude/versions/") {
            return AppIdentity(name: "Claude Code", kind: .commandLineTool, iconBundleID: nil)
        }
        if let e = AppNameTable.systemServices[stem.lowercased()] {
            return AppIdentity(name: e.name, kind: .systemService, iconBundleID: e.iconBundleID)
        }

        let isSystemPath = systemPrefixes.contains { path.hasPrefix($0) } || last.hasSuffix(".xpc")
        if isSystemPath { return AppIdentity(name: "\(stripHelperSuffix(stem)) (sistem)", kind: .systemService, iconBundleID: nil) }

        return AppIdentity(name: toolName(stem: stem, lowerPath: lower, path: path), kind: .commandLineTool, iconBundleID: nil)
    }

    /// Başta/sonda boşluk ve görünmez yön işaretlerini (WhatsApp adı U+200E ile başlar) atar.
    private static func cleaned(_ name: String) -> String {
        let marks: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}"]
        return String(String.UnicodeScalarView(name.unicodeScalars.filter { !marks.contains($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `…/Foo.app/Contents/…/Foo Helper (Renderer).app/…` → `…/Foo.app` (en dıştaki paket). Filtredeki
    /// `IdentityResolver.rollUp` ile aynı kural; eski kayıtlarda iç içe yol kalmışsa ebeveyn uygulamaya bağlar.
    static func outermostApp(of path: String) -> String {
        guard let r = path.range(of: ".app/") else { return path }
        return String(path[..<r.lowerBound]) + ".app"
    }

    /// "Google Chrome Helper", "Foo Helper (Renderer)", "Foo Helper (GPU)" → "Google Chrome", "Foo".
    static func stripHelperSuffix(_ name: String) -> String {
        guard let r = name.range(of: " Helper") else { return name }
        let rest = name[r.upperBound...]
        guard rest.isEmpty || (rest.hasPrefix(" (") && rest.hasSuffix(")")) else { return name }
        let base = String(name[..<r.lowerBound])
        return base.isEmpty ? name : base
    }

    private static func toolName(stem: String, lowerPath: String, path: String) -> String {
        let key = stem.lowercased()
        var name: String
        if let known = AppNameTable.tools[key] {
            name = known
        } else if key == "python" || (key.hasPrefix("python") && key.dropFirst(6).allSatisfy { $0.isNumber || $0 == "." }) {
            name = "Python"
        } else if stem.allSatisfy({ $0.isNumber || $0 == "." }), let parent = versionedParent(path) {
            name = parent
        } else {
            name = stem
        }
        let isDart = key == "dart" || key == "dartvm"
        if isDart, lowerPath.contains("flutter") || lowerPath.contains("/fvm/") { name += " (Flutter)" }
        if lowerPath.contains("/com.raycast.macos/") { name += " (Raycast)" }
        return name
    }

    /// `…/<ad>/versions/2.1.3` → "<ad>" (sürüm numarasıyla adlandırılmış ikililer).
    private static func versionedParent(_ path: String) -> String? {
        let parts = path.split(separator: "/")
        guard let vIndex = parts.lastIndex(of: "versions"), vIndex > 0 else { return nil }
        return String(parts[vIndex - 1])
    }
}
