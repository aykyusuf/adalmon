import SwiftUI

enum MainSection: Hashable, Identifiable {
    case overview, network, history, mobile, rules
    case settings(SettingsSection)

    /// Kenar çubuğundaki sayfalar (sıra aynı zamanda ⌘1…⌘5 sırasıdır).
    static let pages: [MainSection] = [.overview, .network, .history, .mobile, .rules]

    static var allCases: [MainSection] { pages + SettingsSection.allCases.map(MainSection.settings) }

    init?(id: String) {
        guard let match = Self.allCases.first(where: { $0.id == id }) else { return nil }
        self = match
    }

    var id: String {
        switch self {
        case .overview: "overview"
        case .network: "network"
        case .history: "history"
        case .mobile: "mobile"
        case .rules: "rules"
        case .settings(let section): "settings.\(section.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .overview: "Genel bakış"
        case .network: "Ağ kullanımı"
        case .history: "Geçmiş"
        case .mobile: "Mobil veri"
        case .rules: "Kurallar"
        case .settings(let section): section.title
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .network: "arrow.up.arrow.down"
        case .history: "chart.bar.xaxis"
        case .mobile: "antenna.radiowaves.left.and.right"
        case .rules: "shield.lefthalf.filled"
        case .settings(let section): section.symbol
        }
    }

    var tint: Color {
        switch self {
        case .overview: .blue
        case .network: .indigo
        case .history: .purple
        case .mobile: .green
        case .rules: .pink
        case .settings(let section): section.tint
        }
    }

    /// Dock modu kenar çubuğundaki Ayarlar bölümleri. Mobil veri ayarları "Mobil veri" sayfasının altına taşındı;
    /// ayrı Ayarlar penceresi (Dock modu kapalıyken) tüm bölümleri gösterir.
    static let dockSettingsSections: [SettingsSection] = SettingsSection.allCases.filter { $0 != .mobileData }

    /// Dock modunda gösterilemeyen bölümü (eski kayıtlı seçim, `open(.mobileData)`) gösterilebilir karşılığına çevirir.
    var dockCanonical: MainSection {
        if case .settings(.mobileData) = self { .mobile } else { self }
    }

    /// ⌘ ile birlikte kullanılan rakam ("1"…"5"); ayar bölümlerinin kısayolu yoktur.
    var shortcutKey: String? {
        Self.pages.firstIndex(of: self).map { String($0 + 1) }
    }
}
