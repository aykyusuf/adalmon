import Foundation

/// Ağ grafiğinin yüksekliği.
enum ChartHeight: String, Codable, CaseIterable, Sendable, Identifiable {
    case small
    case medium
    case off

    var id: String { rawValue }

    var points: CGFloat? {
        switch self {
        case .small: 40
        case .medium: 56
        case .off: nil
        }
    }

    var displayName: String {
        switch self {
        case .small: "Küçük"
        case .medium: "Orta"
        case .off: "Kapalı"
        }
    }
}
