import AppKit

/// Uygulama anahtarı (bundle yolu ya da çalıştırılabilir yol) → görünen ad ve ikon.
@MainActor
final class AppCatalog {
    static let shared = AppCatalog()

    private var names: [String: String] = [:]
    private var icons: [String: NSImage] = [:]

    private static let knownDaemons: [String: String] = [
        "nsurlsessiond": "Sistem indirmeleri",
        "mDNSResponder": "DNS",
        "softwareupdated": "Yazılım güncelleme",
        "cloudd": "iCloud",
        "bird": "iCloud Drive",
        "photolibraryd": "Fotoğraflar (iCloud)",
        "apsd": "Apple bildirimleri",
        "rapportd": "Yakındaki aygıtlar",
        "trustd": "Sertifika denetimi",
        "com.apple.geod": "Haritalar/konum",
        "commerce": "App Store",
        "appstoreagent": "App Store",
    ]

    func name(for app: String) -> String {
        if let n = names[app] { return n }
        let n = resolveName(app)
        names[app] = n
        return n
    }

    func icon(for app: String) -> NSImage {
        if let i = icons[app] { return i }
        let i: NSImage
        if app.hasSuffix(".app"), FileManager.default.fileExists(atPath: app) {
            i = NSWorkspace.shared.icon(forFile: app)
        } else {
            i = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: nil) ?? NSImage()
        }
        icons[app] = i
        return i
    }

    private func resolveName(_ app: String) -> String {
        let last = (app as NSString).lastPathComponent
        if app.hasSuffix(".app") {
            if let b = Bundle(path: app),
               let n = b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? b.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !n.isEmpty {
                return n
            }
            return (last as NSString).deletingPathExtension
        }
        if let known = Self.knownDaemons[last] { return known }
        if app.contains("/.local/share/claude/") { return "Claude Code" }
        return last.isEmpty ? app : last
    }
}
