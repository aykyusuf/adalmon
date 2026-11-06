import Foundation

/// Panel yoğunluğu: satır yüksekliği, boşluklar ve kart boyutları (8 pt ızgarasına göre).
enum PanelDensity: String, Codable, CaseIterable, Sendable, Identifiable {
    case compact
    case comfortable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: "Kompakt"
        case .comfortable: "Rahat"
        }
    }

    /// Uygulama satırı yüksekliği (pt).
    var rowHeight: CGFloat { self == .compact ? 22 : 30 }
    /// Bölümler arası boşluk.
    var sectionSpacing: CGFloat { self == .compact ? 8 : 12 }
    /// Panel kenar boşluğu.
    var padding: CGFloat { self == .compact ? 12 : 16 }
    /// Uygulama ikonu kenarı.
    var iconSize: CGFloat { self == .compact ? 16 : 20 }
    /// Kart iç boşluğu.
    var cardPadding: CGFloat { self == .compact ? 8 : 12 }
    /// Kartlardaki mini grafiğin yüksekliği.
    var sparklineHeight: CGFloat { self == .compact ? 20 : 28 }
}
