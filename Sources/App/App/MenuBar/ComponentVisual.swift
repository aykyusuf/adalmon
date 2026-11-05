import Foundation

enum ComponentVisual: String, Codable, CaseIterable, Identifiable, Sendable {
    case text, stacked2, iconValue, bar, hbar, ring, sparkline, dot
    /// Compact layouts of the simple metric cards (`MetricLayout`).
    case oneLine, labelAbove, symbolStack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: "Metin"
        case .stacked2: "İki satır"
        case .iconValue: "İkon"
        case .bar: "Çubuk"
        case .hbar: "Yatay çubuk"
        case .ring: "Halka"
        case .sparkline: "Grafik"
        case .dot: "Nokta"
        case .oneLine: "Tek satır"
        case .labelAbove: "Etiket üstte"
        case .symbolStack: "Simge"
        }
    }

    var hasGraphic: Bool { !isCompact && self != .text && self != .stacked2 }

    /// Compact card layouts: up to three values, units shortened.
    var isCompact: Bool { self == .oneLine || self == .labelAbove || self == .symbolStack }

    var allowsThirdLine: Bool { isCompact }

    var allowsSecondLine: Bool { self != .hbar && self != .dot }

    /// The single validity rule used by the library, the inspector chips and the tests.
    func supports(primary: DataField, secondary: DataField?) -> Bool {
        if secondary != nil, !allowsSecondLine { return false }
        if secondary == .connection { return false }
        if isCompact { return primary != .connection }
        if primary == .connection { return self == .dot || self == .iconValue || self == .text }
        if self == .sparkline { return primary.hasHistory }
        return true
    }
}
