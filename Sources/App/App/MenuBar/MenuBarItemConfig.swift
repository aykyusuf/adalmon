import Foundation

/// Menü çubuğundaki tek bir widget'ın ayarları.
struct MenuBarItemConfig: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var metric: MetricKind
    var style: WidgetStyle
    var colorMode: ColorMode = .monochrome
    var customColor: RGBAColor = .teal
    var gradientStart: RGBAColor = .green
    var gradientEnd: RGBAColor = .red
    var showLabel = false
    /// Grafik/çubuk/halka yanında sayısal değeri de göster.
    var showValue = true
    /// Metni de grafik rengiyle boya.
    var colorizeText = false
    var enabled = true
    var thresholds = Thresholds()
    /// Yalnızca ağ: gösterilen yön ve değer kaynağı.
    var networkDirection: NetworkDirection = .both
    var networkSource: NetworkValueSource = .speed
    /// Yalnızca sıcaklık: sensör grubu.
    var temperatureSource: TemperatureSource = .cpu

    init(metric: MetricKind, style: WidgetStyle? = nil, colorMode: ColorMode = .monochrome,
         customColor: RGBAColor = .teal, gradientStart: RGBAColor = .green, gradientEnd: RGBAColor = .red,
         showLabel: Bool = false, showValue: Bool = true, colorizeText: Bool = false,
         networkDirection: NetworkDirection = .both, networkSource: NetworkValueSource = .speed,
         temperatureSource: TemperatureSource = .cpu) {
        self.metric = metric
        self.style = style.flatMap { metric.supports($0) ? $0 : nil } ?? metric.supportedStyles[0]
        self.colorMode = colorMode
        self.customColor = customColor
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.showLabel = showLabel
        self.showValue = showValue
        self.colorizeText = colorizeText
        self.thresholds = metric.defaultThresholds
        self.networkDirection = networkDirection
        self.networkSource = networkSource
        self.temperatureSource = temperatureSource
    }

    private enum CodingKeys: String, CodingKey {
        case id, metric, style, colorMode, customColor, gradientStart, gradientEnd
        case showLabel, showValue, colorizeText, enabled, thresholds
        case networkDirection, networkSource, temperatureSource
    }

    /// Eksik alanlar varsayılana düşer; desteklenmeyen stil metriğin varsayılanına çekilir.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let decodedMetric = try c.decode(MetricKind.self, forKey: .metric)
        let decodedStyle = try c.decodeIfPresent(WidgetStyle.self, forKey: .style)
        metric = decodedMetric
        style = decodedStyle.flatMap { decodedMetric.supports($0) ? $0 : nil } ?? decodedMetric.supportedStyles[0]
        colorMode = try c.decodeIfPresent(ColorMode.self, forKey: .colorMode) ?? .monochrome
        customColor = try c.decodeIfPresent(RGBAColor.self, forKey: .customColor) ?? .teal
        gradientStart = try c.decodeIfPresent(RGBAColor.self, forKey: .gradientStart) ?? .green
        gradientEnd = try c.decodeIfPresent(RGBAColor.self, forKey: .gradientEnd) ?? .red
        showLabel = try c.decodeIfPresent(Bool.self, forKey: .showLabel) ?? false
        showValue = try c.decodeIfPresent(Bool.self, forKey: .showValue) ?? true
        colorizeText = try c.decodeIfPresent(Bool.self, forKey: .colorizeText) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        thresholds = try c.decodeIfPresent(Thresholds.self, forKey: .thresholds) ?? decodedMetric.defaultThresholds
        networkDirection = try c.decodeIfPresent(NetworkDirection.self, forKey: .networkDirection) ?? .both
        networkSource = try c.decodeIfPresent(NetworkValueSource.self, forKey: .networkSource) ?? .speed
        temperatureSource = try c.decodeIfPresent(TemperatureSource.self, forKey: .temperatureSource) ?? .cpu
    }

    /// Menü çubuğunda çizilen kısa etiket (ağda kaynağa, sıcaklıkta sensöre göre).
    var label: String {
        switch metric {
        case .network: networkSource.shortLabel
        case .temperature: temperatureSource.shortLabel
        default: metric.shortLabel
        }
    }

    /// `id` dışındaki tüm alanlar aynı mı (preset eşleştirmesi için).
    func isEquivalent(to other: MenuBarItemConfig) -> Bool {
        var a = self
        a.id = other.id
        return a == other
    }
}
