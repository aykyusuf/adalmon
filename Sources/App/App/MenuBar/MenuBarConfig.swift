import Foundation

struct MenuBarConfig: Codable, Equatable, Sendable {
    static let spacingRange: ClosedRange<Double> = 2...10
    static let labelOpacityRange: ClosedRange<Double> = 0.6...1

    var components: [MenuBarComponent]
    var displayMode: MenuBarDisplayMode = .combined
    var spacing: Double = 6
    var labelOpacity: Double = 0.8
    var showUnits = true
    /// Tıklayınca: metriğin kendi paneli (varsayılan) ya da birleşik panel.
    var clickMode: PanelClickMode = .perMetric

    init(components: [MenuBarComponent], displayMode: MenuBarDisplayMode = .combined,
         spacing: Double = 6, labelOpacity: Double = 0.8, showUnits: Bool = true,
         clickMode: PanelClickMode = .perMetric) {
        self.clickMode = clickMode
        self.components = components
        self.displayMode = displayMode
        self.spacing = spacing
        self.labelOpacity = labelOpacity
        self.showUnits = showUnits
    }

    private enum CodingKeys: String, CodingKey { case components, items, displayMode, spacing, labelOpacity, showUnits, clickMode }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let lossy = try c.decodeIfPresent([Lossy<MenuBarComponent>].self, forKey: .components) {
            // Çözülemeyen tek bileşen (ör. eski/yeni sürümdeki bilinmeyen alan) bütün listeyi ve ayarları düşürmesin.
            self.components = lossy.compactMap(\.value)
        } else {
            // Round-2 JSON stored `items`; migrate each one into a component.
            let items = try c.decodeIfPresent([MenuBarItemConfig].self, forKey: .items) ?? []
            components = items.map(MenuBarComponent.init(legacy:))
        }
        displayMode = try c.decodeIfPresent(MenuBarDisplayMode.self, forKey: .displayMode) ?? .combined
        spacing = try c.decodeIfPresent(Double.self, forKey: .spacing) ?? 6
        labelOpacity = try c.decodeIfPresent(Double.self, forKey: .labelOpacity) ?? 0.8
        showUnits = try c.decodeIfPresent(Bool.self, forKey: .showUnits) ?? true
        clickMode = (try? c.decodeIfPresent(PanelClickMode.self, forKey: .clickMode)) ?? .perMetric
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(components, forKey: .components)
        try c.encode(displayMode, forKey: .displayMode)
        try c.encode(spacing, forKey: .spacing)
        try c.encode(labelOpacity, forKey: .labelOpacity)
        try c.encode(showUnits, forKey: .showUnits)
        try c.encode(clickMode, forKey: .clickMode)
    }

    var enabledComponents: [MenuBarComponent] { components.filter(\.enabled) }

    var clampedSpacing: Double { min(max(spacing, Self.spacingRange.lowerBound), Self.spacingRange.upperBound) }
    var clampedLabelOpacity: Double { min(max(labelOpacity, Self.labelOpacityRange.lowerBound), Self.labelOpacityRange.upperBound) }

    /// Fresh install / reset: the simple metric cards' defaults.
    static let `default` = MenuBarConfig(components: MetricCardConfig.components(for: MetricCardConfig.defaults))
}
