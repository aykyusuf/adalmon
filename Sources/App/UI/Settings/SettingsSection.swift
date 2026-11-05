import SwiftUI

/// Ayarlar penceresinin kenar çubuğu bölümleri.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case menuBar, panel, throttle, mobileData, filter, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: "Menü çubuğu"
        case .panel: "Panel"
        case .throttle: "Hız sınırı"
        case .mobileData: "Mobil veri"
        case .filter: "Filtre"
        case .general: "Genel"
        }
    }

    var symbol: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .panel: "rectangle.split.3x1"
        case .throttle: "speedometer"
        case .mobileData: "antenna.radiowaves.left.and.right"
        case .filter: "line.3.horizontal.decrease"
        case .general: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .menuBar: .blue
        case .panel: .teal
        case .throttle: .orange
        case .mobileData: .green
        case .filter: .orange
        case .general: .gray
        }
    }
}
