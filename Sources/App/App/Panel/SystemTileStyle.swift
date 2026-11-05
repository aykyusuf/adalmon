import Foundation

/// Sistem bölümünün görünümü.
enum SystemTileStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Tek satırda dört küçük karo (değer + minik grafik).
    case compactTiles
    /// 2×2 büyük kart.
    case cards
    /// Her metrik için tek satır + çubuk.
    case rows

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compactTiles: "Küçük karolar"
        case .cards: "Kartlar"
        case .rows: "Satırlar"
        }
    }
}
