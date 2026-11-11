import Foundation

/// The simple, per-metric menu bar settings. Not stored: it is derived from and turned into
/// `MenuBarComponent`s (see `MetricCardConfig+Mapping`), so the component list stays the single source of truth.
struct MetricCardConfig: Equatable, Identifiable, Sendable {
    var kind: MetricCardKind
    var shown: Bool
    /// Selected values in `kind.options` order (network: instant fields; see `networkSource`).
    var fields: [DataField]
    var showGraph = false
    var layout: MetricLayout = .inline
    var thresholdColor = false
    /// Özel eşikler; nil = öndeki değerin varsayılanı (ölçek değişince nil'e döner).
    var thresholds: Thresholds?
    /// Eşik modunda seviye başına renk.
    var levelColors = ThresholdColors()
    var showLabel = true
    var networkSource: NetworkCardSource = .speed
    /// Pil kartı: kalan / dolum süresini de göster.
    var showTime = false
    /// Pil kartı: menü çubuğundaki sıvı animasyonu.
    var batteryAnimation: BatteryGlyphOptions.Animation = .live
    /// Pil kartı: animasyon stili ve dolgu renkleri (nil = otomatik).
    var batteryStyle: BatteryGlyphOptions.Style = .liquid
    var batteryFill: RGBAColor?
    var batterySecond: RGBAColor?

    var id: MetricCardKind { kind }

    init(_ kind: MetricCardKind, shown: Bool, fields: [DataField], showGraph: Bool = false, layout: MetricLayout = .inline,
         thresholdColor: Bool = false, showLabel: Bool = true, networkSource: NetworkCardSource = .speed, showTime: Bool = false) {
        self.showTime = showTime
        self.kind = kind
        self.shown = shown
        self.fields = fields
        self.showGraph = showGraph
        self.layout = layout
        self.thresholdColor = thresholdColor
        self.showLabel = showLabel
        self.networkSource = networkSource
    }

    /// Fresh install / reset: connection dot, CPU % + °, used memory, two-line network speed.
    static let defaults: [MetricCardConfig] = [
        MetricCardConfig(.connection, shown: true, fields: [], showLabel: false),
        MetricCardConfig(.cpu, shown: true, fields: [.cpu, .cpuTemp]),
        MetricCardConfig(.memory, shown: true, fields: [.memoryUsed]),
        MetricCardConfig(.network, shown: true, fields: [.download, .upload], layout: .symbol),
        MetricCardConfig(.gpu, shown: false, fields: [.gpu, .gpuTemp]),
        MetricCardConfig(.disk, shown: false, fields: [.diskFree]),
        MetricCardConfig(.mobile, shown: false, fields: [.mobileUsed]),
        MetricCardConfig(.temperature, shown: false, fields: [.ssdTemp]),
        // Mac pili: "[100]" kapsülü; renkler (düşük / şarj) varsayılan açık.
        MetricCardConfig(.battery, shown: false, fields: [.batteryLevel], thresholdColor: true, showLabel: false),
    ]

    static func defaultCard(_ kind: MetricCardKind) -> MetricCardConfig {
        defaults.first { $0.kind == kind } ?? MetricCardConfig(kind, shown: false, fields: Array(kind.options.prefix(1)))
    }

    func isSelected(_ field: DataField) -> Bool { fields.contains(field) }

    /// Sets a value checkbox, keeping `kind.options` order. The last remaining value (or the graph) can't be removed.
    mutating func set(_ field: DataField, selected: Bool) {
        var set = Set(fields)
        if selected { set.insert(field) } else { set.remove(field) }
        let next = kind.options.filter(set.contains)
        guard !next.isEmpty || showGraph || kind == .connection else { return }
        let old = thresholdField
        fields = next
        resetThresholdsIfScaleChanged(from: old)
    }

    mutating func setGraph(_ on: Bool) {
        guard on || !fields.isEmpty else { return }
        let old = thresholdField
        showGraph = on
        resetThresholdsIfScaleChanged(from: old)
    }

    /// Özel eşiklerin ölçeğini belirleyen alan: menü çubuğundaki ilk değer (yalnız grafik varsa grafik alanı).
    var thresholdField: DataField? {
        renderFields.first ?? (showGraph ? kind.graphField : nil)
    }

    /// Kartta gösterilen/düzenlenen eşikler.
    var effectiveThresholds: Thresholds {
        get { thresholds ?? thresholdField?.defaultThresholds ?? Thresholds() }
        set { thresholds = newValue == thresholdField?.defaultThresholds ? nil : newValue }
    }

    /// % → °C gibi ölçek değişince özel eşikler anlamını yitirir; varsayılana döner.
    private mutating func resetThresholdsIfScaleChanged(from old: DataField?) {
        if old?.defaultThresholds != thresholdField?.defaultThresholds { thresholds = nil }
    }

    func canDeselect(_ field: DataField) -> Bool { fields != [field] || showGraph }
    var canDeselectGraph: Bool { !fields.isEmpty }
}
