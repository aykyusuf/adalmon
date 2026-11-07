import Foundation

/// Ekran koruyucunun hangi videoları kullanacağı.
enum SaverSource: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Duvar kâğıdıyla aynı: tek içerik modunda seçili video, sırayla/karışıkta kütüphanedeki tüm videolar.
    case sameAsWallpaper
    /// Kütüphaneden elle seçilenler.
    case picked

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sameAsWallpaper: "Duvar kâğıdıyla aynı (önerilen)"
        case .picked: "Farklı videolar"
        }
    }
}

struct SaverSettings: Codable, Equatable, Hashable, Sendable {
    var source: SaverSource = .sameAsWallpaper
    var pickedIDs: [UUID] = []
    var shuffle = true
    /// Ekran koruyucu bitince legacyScreenSaver sürecini kapat (macOS sızıntısına çare). Sorun olursa kapatılabilir.
    var hostExitOnStop = true
}
