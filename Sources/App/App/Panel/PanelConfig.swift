import Foundation

/// Menü çubuğu panelinin kullanıcı ayarları. UserDefaults'ta JSON olarak ("panelConfig") saklanır.
struct PanelConfig: Codable, Equatable, Sendable {
    static let rowCountRange = 0...15

    /// Sıralı bölümler; her bölüm tam bir kez bulunur.
    var sections: [PanelSectionItem] { didSet { sections = Self.normalized(sections) } }
    /// Başlığından daraltılmış bölümler.
    var collapsed: Set<PanelSection>
    var density: PanelDensity
    var last60Rows: Int { didSet { last60Rows = Self.clamp(last60Rows) } }
    var todayRows: Int { didSet { todayRows = Self.clamp(todayRows) } }
    var tileStyle: SystemTileStyle
    var showTemperatures: Bool
    var chartHeight: ChartHeight

    static let defaultSections: [PanelSectionItem] = PanelSection.allCases.map { PanelSectionItem(section: $0, isVisible: true) }

    init(sections: [PanelSectionItem] = PanelConfig.defaultSections,
         collapsed: Set<PanelSection> = [],
         density: PanelDensity = .compact,
         last60Rows: Int = 3,
         todayRows: Int = 5,
         tileStyle: SystemTileStyle = .compactTiles,
         showTemperatures: Bool = true,
         chartHeight: ChartHeight = .small) {
        self.sections = Self.normalized(sections)
        self.collapsed = collapsed
        self.density = density
        self.last60Rows = Self.clamp(last60Rows)
        self.todayRows = Self.clamp(todayRows)
        self.tileStyle = tileStyle
        self.showTemperatures = showTemperatures
        self.chartHeight = chartHeight
    }

    private enum CodingKeys: String, CodingKey {
        case sections, collapsed, density, last60Rows, todayRows, tileStyle, showTemperatures, chartHeight
    }

    /// Eksik ya da bilinmeyen alanlar varsayılana düşer; böylece eski kayıtlar yeni sürümde de açılır.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PanelConfig()
        self.init(
            sections: (try? c.decodeIfPresent([PanelSectionItem].self, forKey: .sections)) ?? d.sections,
            collapsed: (try? c.decodeIfPresent(Set<PanelSection>.self, forKey: .collapsed)) ?? d.collapsed,
            density: (try? c.decodeIfPresent(PanelDensity.self, forKey: .density)) ?? d.density,
            last60Rows: (try? c.decodeIfPresent(Int.self, forKey: .last60Rows)) ?? d.last60Rows,
            todayRows: (try? c.decodeIfPresent(Int.self, forKey: .todayRows)) ?? d.todayRows,
            tileStyle: (try? c.decodeIfPresent(SystemTileStyle.self, forKey: .tileStyle)) ?? d.tileStyle,
            showTemperatures: (try? c.decodeIfPresent(Bool.self, forKey: .showTemperatures)) ?? d.showTemperatures,
            chartHeight: (try? c.decodeIfPresent(ChartHeight.self, forKey: .chartHeight)) ?? d.chartHeight
        )
    }

    /// Görünür bölümler, sırasıyla.
    var visibleSections: [PanelSection] { sections.filter(\.isVisible).map(\.section) }

    func isVisible(_ section: PanelSection) -> Bool {
        sections.first { $0.section == section }?.isVisible ?? false
    }

    func isCollapsed(_ section: PanelSection) -> Bool { collapsed.contains(section) }

    mutating func setVisible(_ section: PanelSection, _ visible: Bool) {
        guard let i = sections.firstIndex(where: { $0.section == section }) else { return }
        sections[i].isVisible = visible
    }

    mutating func toggleCollapsed(_ section: PanelSection) {
        if collapsed.contains(section) { collapsed.remove(section) } else { collapsed.insert(section) }
    }

    /// Bölümü bir sıra yukarı (-1) ya da aşağı (+1) taşır.
    mutating func move(_ section: PanelSection, by delta: Int) {
        guard let i = sections.firstIndex(where: { $0.section == section }) else { return }
        let j = i + delta
        guard sections.indices.contains(j) else { return }
        sections.swapAt(i, j)
    }

    static func clamp(_ rows: Int) -> Int { min(max(rows, rowCountRange.lowerBound), rowCountRange.upperBound) }

    /// Yinelenenleri atar, eksik bölümleri sona (görünür olarak) ekler.
    static func normalized(_ items: [PanelSectionItem]) -> [PanelSectionItem] {
        var seen = Set<PanelSection>()
        var result = items.filter { seen.insert($0.section).inserted }
        for section in PanelSection.allCases where !seen.contains(section) {
            result.append(PanelSectionItem(section: section, isVisible: true))
        }
        return result
    }
}
