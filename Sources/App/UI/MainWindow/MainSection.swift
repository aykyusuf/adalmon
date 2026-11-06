import SwiftUI

/// Ana pencere kenar çubuğu girişleri: üç sayfa ve "Ayarlar" başlığı altındaki Ayarlar bölümleri.
enum MainSection: Hashable, Identifiable {
    case overview, network, mobile
    case settings(SettingsSection)

    /// Üstteki Ayarlar dışı sayfalar.
    static let pages: [MainSection] = [.overview, .network, .mobile]

    /// Kenar çubuğundaki tüm girişler, sırayla.
    static var allCases: [MainSection] { pages + SettingsSection.allCases.map(MainSection.settings) }

    var id: String {
        switch self {
        case .overview: "overview"
        case .network: "network"
        case .mobile: "mobile"
        case .settings(let section): "settings.\(section.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .overview: "Genel bakış"
        case .network: "Ağ kullanımı"
        case .mobile: "Mobil veri"
        case .settings(let section): section.title
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .network: "arrow.up.arrow.down"
        case .mobile: "antenna.radiowaves.left.and.right"
        case .settings(let section): section.symbol
        }
    }

    var tint: Color {
        switch self {
        case .overview: .blue
        case .network: .indigo
        case .mobile: .green
        case .settings(let section): section.tint
        }
    }
}
