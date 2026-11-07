import Foundation

/// Döngü sonunda / içerik değişirken geçiş biçimi.
enum LoopTransition: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Sert geçiş (tek videoda kesintisiz `AVPlayerLooper`).
    case off
    /// Çapraz geçiş (opaklık).
    case crossfade

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Kapalı"
        case .crossfade: "Çapraz geçiş"
        }
    }
}
