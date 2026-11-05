import Foundation

/// Menü çubuğu panelinde sıralanabilen ve gizlenebilen bölümler.
enum PanelSection: String, Codable, CaseIterable, Sendable, Identifiable {
    case system
    case networkChart
    case mobileCap
    case blockedApps
    case last60
    case today

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "Sistem"
        case .networkChart: "Ağ grafiği"
        case .mobileCap: "Mobil kota"
        case .blockedApps: "Engellenenler"
        case .last60: "Son 60 sn"
        case .today: "Bugün"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "cpu"
        case .networkChart: "chart.xyaxis.line"
        case .mobileCap: "antenna.radiowaves.left.and.right"
        case .blockedApps: "hand.raised"
        case .last60: "clock"
        case .today: "calendar"
        }
    }
}
