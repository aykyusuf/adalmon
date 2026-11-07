import Foundation

/// Görev Yöneticisi gibi gruplar: arayüzü olan uygulamalar, arka plan işlemleri, macOS sistem süreçleri.
enum ProcessCategory: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case app, background, system

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .app: "Uygulamalar"
        case .background: "Arka plan işlemleri"
        case .system: "Sistem (macOS)"
        }
    }

    /// Anahtar `.app` yolu ve çalışan "normal" uygulamalar kümesinden kategori çıkarır (saf mantık).
    static func classify(key: String, regularAppPaths: Set<String>) -> ProcessCategory {
        if key == ResourceKeys.system { return .system }
        if regularAppPaths.contains(key) { return .app }
        if key.hasPrefix("/System/") || AppNaming.identity(forApp: key).kind == .systemService { return .system }
        return .background
    }
}
