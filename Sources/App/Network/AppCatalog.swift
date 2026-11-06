import AppKit

/// Uygulama anahtarı (bundle yolu ya da çalıştırılabilir yol) → görünen ad ve ikon.
/// Ad/tür kuralları `AppNaming`'de (saf mantık), ikon çizimi `AppIconFactory`'de. Anahtar hiç değişmez.
@MainActor
final class AppCatalog {
    static let shared = AppCatalog()

    private var identities: [String: AppIdentity] = [:]
    private var icons: [String: NSImage] = [:]

    func identity(for app: String) -> AppIdentity {
        if let i = identities[app] { return i }
        let i = AppNaming.identity(forApp: app, bundleName: Self.bundleDisplayName)
        identities[app] = i
        return i
    }

    func name(for app: String) -> String { identity(for: app).name }

    func icon(for app: String) -> NSImage {
        if let i = icons[app] { return i }
        let i = AppIconFactory.icon(for: identity(for: app), appPath: app)
        icons[app] = i
        return i
    }

    private static func bundleDisplayName(_ path: String) -> String? {
        guard let b = Bundle(path: path) else { return nil }
        return b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? b.object(forInfoDictionaryKey: "CFBundleName") as? String
    }
}
