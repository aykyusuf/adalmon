import Foundation

/// Menü çubuğu panelinin kullanıcı ayarları. UserDefaults'ta JSON olarak ("panelConfig") saklanır.
struct PanelConfig: Codable, Equatable, Sendable {
    static let rowCountRange = 0...15

    /// Sıralı bölümler; her bölüm tam bir kez bulunur.
    var sections: [PanelSectionItem] { didSet { sections = Self.normalized(sections) } }
    /// Sistem kartları ızgarasındaki sıralı kartlar; her kart tam bir kez bulunur.
    var cards: [PanelCardItem] { didSet { cards = Self.normalized(cards) } }
    /// Başlığından daraltılmış bölümler.
    var collapsed: Set<PanelSection>
    var density: PanelDensity
    /// Metrik panellerinde (pil ayrıntı bölümleri vb.) daraltılmış bölüm kimlikleri; hatırlanır.
    var detailCollapsed: Set<String> = []
    /// Varsayılanı "kapalı" olan bölümlerden kullanıcının açtıkları (ör. "battery.info").
    var detailExpanded: Set<String> = []
    /// Panel zemini: koyu opak (varsayılan) ya da cam.
    var background: PanelBackground = .default
    var last60Rows: Int { didSet { last60Rows = Self.clamp(last60Rows) } }
    var todayRows: Int { didSet { todayRows = Self.clamp(todayRows) } }

    static let defaultSections: [PanelSectionItem] = PanelSection.allCases.map { PanelSectionItem(section: $0, isVisible: true) }
    static let defaultCards: [PanelCardItem] = [.cpu, .gpu, .memory, .temperature, .download, .upload, .disk]
        .map { PanelCardItem(kind: $0, isVisible: $0.isVisibleByDefault) }

    init(sections: [PanelSectionItem] = PanelConfig.defaultSections,
         cards: [PanelCardItem] = PanelConfig.defaultCards,
         collapsed: Set<PanelSection> = [],
         density: PanelDensity = .compact,
         last60Rows: Int = 3,
         todayRows: Int = 5,
         detailCollapsed: Set<String> = [],
         detailExpanded: Set<String> = [],
         background: PanelBackground = .default) {
        self.detailCollapsed = detailCollapsed
        self.detailExpanded = detailExpanded
        self.background = background
        self.sections = Self.normalized(sections)
        self.cards = Self.normalized(cards)
        self.collapsed = collapsed
        self.density = density
        self.last60Rows = Self.clamp(last60Rows)
        self.todayRows = Self.clamp(todayRows)
    }

    private enum CodingKeys: String, CodingKey {
        case sections, cards, collapsed, density, last60Rows, todayRows, detailCollapsed, detailExpanded, background
    }

    /// Eksik ya da bilinmeyen alanlar varsayılana düşer; böylece eski kayıtlar yeni sürümde de açılır.
    /// Bilinmeyen bölüm/kart değerleri (ör. kaldırılan "networkChart") tek tek atılır, kalan sıra korunur.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PanelConfig()
        let sections = (try? c.decodeIfPresent([Lossy<PanelSectionItem>].self, forKey: .sections))?.compactMap(\.value)
        let cards = (try? c.decodeIfPresent([Lossy<PanelCardItem>].self, forKey: .cards))?.compactMap(\.value)
        let collapsed = (try? c.decodeIfPresent([Lossy<PanelSection>].self, forKey: .collapsed))?.compactMap(\.value)
        self.init(
            sections: sections ?? d.sections,
            cards: cards ?? d.cards,
            collapsed: collapsed.map(Set.init) ?? d.collapsed,
            density: (try? c.decodeIfPresent(PanelDensity.self, forKey: .density)) ?? d.density,
            last60Rows: (try? c.decodeIfPresent(Int.self, forKey: .last60Rows)) ?? d.last60Rows,
            todayRows: (try? c.decodeIfPresent(Int.self, forKey: .todayRows)) ?? d.todayRows,
            detailCollapsed: (try? c.decodeIfPresent(Set<String>.self, forKey: .detailCollapsed)) ?? [],
            detailExpanded: (try? c.decodeIfPresent(Set<String>.self, forKey: .detailExpanded)) ?? [],
            background: (try? c.decodeIfPresent(PanelBackground.self, forKey: .background)) ?? .default
        )
    }

    /// Görünür bölümler, sırasıyla.
    var visibleSections: [PanelSection] { sections.filter(\.isVisible).map(\.section) }
    /// Görünür kartlar, sırasıyla.
    var visibleCards: [PanelCardKind] { cards.filter(\.isVisible).map(\.kind) }

    func isVisible(_ section: PanelSection) -> Bool {
        sections.first { $0.section == section }?.isVisible ?? false
    }

    func isVisible(_ card: PanelCardKind) -> Bool {
        cards.first { $0.kind == card }?.isVisible ?? false
    }

    func isCollapsed(_ section: PanelSection) -> Bool { collapsed.contains(section) }

    /// `defaultCollapsed`: bölümün hiç dokunulmamış hali (ör. "Pil bilgisi" kapalı başlar).
    func isDetailCollapsed(_ id: String, defaultCollapsed: Bool = false) -> Bool {
        if defaultCollapsed { return !detailExpanded.contains(id) }
        return detailCollapsed.contains(id)
    }

    mutating func toggleDetailCollapsed(_ id: String, defaultCollapsed: Bool = false) {
        if isDetailCollapsed(id, defaultCollapsed: defaultCollapsed) {
            detailCollapsed.remove(id)
            detailExpanded.insert(id)
        } else {
            detailExpanded.remove(id)
            detailCollapsed.insert(id)
        }
    }

    mutating func setVisible(_ section: PanelSection, _ visible: Bool) {
        guard let i = sections.firstIndex(where: { $0.section == section }) else { return }
        sections[i].isVisible = visible
    }

    mutating func setVisible(_ card: PanelCardKind, _ visible: Bool) {
        guard let i = cards.firstIndex(where: { $0.kind == card }) else { return }
        cards[i].isVisible = visible
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

    /// Kartı bir sıra yukarı (-1) ya da aşağı (+1) taşır.
    mutating func move(_ card: PanelCardKind, by delta: Int) {
        guard let i = cards.firstIndex(where: { $0.kind == card }) else { return }
        let j = i + delta
        guard cards.indices.contains(j) else { return }
        cards.swapAt(i, j)
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

    /// Yinelenenleri atar, eksik kartları sona ekler (yalnızca varsayılan olarak görünenler görünür).
    static func normalized(_ items: [PanelCardItem]) -> [PanelCardItem] {
        var seen = Set<PanelCardKind>()
        var result = items.filter { seen.insert($0.kind).inserted }
        for kind in PanelCardKind.allCases where !seen.contains(kind) {
            result.append(PanelCardItem(kind: kind, isVisible: kind.isVisibleByDefault))
        }
        return result
    }
}

/// Bilinmeyen değeri hata vermek yerine nil olarak çözen sarmalayıcı.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
