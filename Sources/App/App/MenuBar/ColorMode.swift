import Foundation

/// Widget'ın grafik (ve istenirse metin) rengi nasıl seçilir.
enum ColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Menü çubuğunun görünümüne uyan etiket rengi.
    case monochrome
    /// Sistem vurgu rengi.
    case accent
    /// Eşiğe göre yeşil / turuncu / kırmızı.
    case threshold
    /// Kullanıcının seçtiği tek renk.
    case custom
    /// İki durak arası, değere göre ara renk.
    case gradient

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monochrome: "Tek renk"
        case .accent: "Vurgu rengi"
        case .threshold: "Eşik"
        case .custom: "Özel renk"
        case .gradient: "Geçişli"
        }
    }
}
