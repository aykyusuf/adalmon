import CoreGraphics
import Foundation

/// Bir ekranın kararlı tanımı. `key` = CGDisplayCreateUUIDFromDisplayID (NSScreen kimliğine güvenilmez);
/// ayna ekranlar aynı UUID'yi paylaşır, bu yüzden bir pencere yeter.
struct WallpaperScreenInfo: Equatable, Sendable, Identifiable {
    var key: String
    var name: String
    /// Piksel cinsinden boyut (ölçekle çarpılmış).
    var pixelSize: CGSize
    var scale: CGFloat
    /// Global ekran koordinatlarında (sol üst orijin) sınırlar: `CGDisplayBounds`.
    var cgBounds: CGRect
    var isMain: Bool = false

    var id: String { key }
    var resolutionText: String { "\(Int(pixelSize.width)) × \(Int(pixelSize.height))" }
}

enum ScreenMapping {
    /// Ayna ekranları (aynı anahtar) tek ekrana indirger; sıra korunur.
    static func unique(_ screens: [WallpaperScreenInfo]) -> [WallpaperScreenInfo] {
        var seen = Set<String>()
        return screens.filter { seen.insert($0.key).inserted }
    }

    /// Ekran → içerik. `sameOnAll` açıksa `defaultItem` hepsinde; kapalıysa ekran başına atama, yoksa `defaultItem`.
    /// Kütüphanede olmayan (silinmiş) atamalar yok sayılır.
    static func assignments(screens: [WallpaperScreenInfo], sameOnAll: Bool, defaultItem: UUID?,
                            perScreen: [String: UUID], available: Set<UUID>) -> [String: UUID] {
        var result: [String: UUID] = [:]
        let fallback = defaultItem.flatMap { available.contains($0) ? $0 : nil }
        for screen in unique(screens) {
            let chosen = sameOnAll ? nil : perScreen[screen.key].flatMap { available.contains($0) ? $0 : nil }
            if let item = chosen ?? fallback { result[screen.key] = item }
        }
        return result
    }
}
