import Foundation

/// How a simple metric card draws its values in the menu bar.
enum MetricLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// `CPU %22 · 33°`: label once, values on one line.
    case inline
    /// Each value in its own column with a tiny label above (Stats "Mini" style).
    case labelAbove
    /// SF Symbol followed by the values stacked in two lines.
    case symbol

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inline: "Tek satır"
        case .labelAbove: "Etiket üstte"
        case .symbol: "Simge"
        }
    }

    var visual: ComponentVisual {
        switch self {
        case .inline: .oneLine
        case .labelAbove: .labelAbove
        case .symbol: .symbolStack
        }
    }
}
