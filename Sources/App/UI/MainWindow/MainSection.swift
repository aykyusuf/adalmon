import SwiftUI

enum MainSection: Hashable, Identifiable {
    case overview, network, history, mobile, rules, processes, battery, wallpaper, agentOffice
    case settings(SettingsSection)

    /// Kenar çubuğundaki sayfalar (sıra aynı zamanda ⌘1…⌘9 sırasıdır).
    static let pages: [MainSection] = [.overview, .network, .history, .mobile, .rules, .processes, .battery, .wallpaper, .agentOffice]

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
        case .processes: "processes"
        case .battery: "battery"
        case .wallpaper: "wallpaper"
        case .agentOffice: "agentOffice"
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
        case .processes: "Süreçler"
        case .battery: "Pil"
        case .wallpaper: "Duvar kâğıdı"
        case .agentOffice: "Ajan ofisi"
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
        case .processes: "waveform.path.ecg.rectangle"
        case .battery: "battery.100percent.bolt"
        case .wallpaper: "photo.on.rectangle.angled"
        case .agentOffice: "building.2"
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
        case .processes: .orange
        case .battery: .green
        case .wallpaper: .teal
        case .agentOffice: .purple
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

    /// ⌘ ile birlikte kullanılan rakam ("1"…"9"); ayar bölümlerinin kısayolu yoktur.
    var shortcutKey: String? {
        Self.pages.firstIndex(of: self).map { String($0 + 1) }
    }
}
