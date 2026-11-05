import Foundation

extension MenuBarComponent {
    /// Maps a round-2 `MenuBarItemConfig` (saved JSON `items`) to a component, keeping its id,
    /// colors, thresholds and enabled state.
    init(legacy item: MenuBarItemConfig) {
        let (primary, secondary) = Self.legacyFields(item)
        self.init(primary, secondary, visual: Self.legacyVisual(item, hasSecondary: secondary != nil),
                  colorMode: item.colorMode, colorTarget: item.colorizeText ? .both : .visual,
                  customColor: item.customColor, gradientStart: item.gradientStart, gradientEnd: item.gradientEnd,
                  showLabel: item.showLabel, showValue: item.showValue)
        id = item.id
        enabled = item.enabled
        thresholds = item.thresholds
        let isTwoDirectionSpeed = item.metric == .network && secondary != nil
            && (item.style == .speedTwoLine || item.style == .speedOneLine)
        if isTwoDirectionSpeed { showLabel = true }
        if item.metric == .network && item.style == .networkChart { showValue = false }
        self = normalized()
    }

    private static func legacyFields(_ item: MenuBarItemConfig) -> (DataField, DataField?) {
        switch item.metric {
        case .cpu: return (.cpu, nil)
        case .gpu: return (.gpu, nil)
        case .memory: return (.memoryPercent, nil)
        case .disk: return (.diskPercent, nil)
        case .mobileData: return (.mobileUsed, nil)
        case .connection: return (.connection, nil)
        case .temperature:
            let field: DataField = switch item.temperatureSource {
            case .cpu: .cpuTemp
            case .cpuMax: .cpuMaxTemp
            case .gpu: .gpuTemp
            case .ssd: .ssdTemp
            case .battery: .batteryTemp
            }
            return (field, nil)
        case .network:
            let (down, up): (DataField, DataField) = switch item.networkSource {
            case .speed: (.download, .upload)
            case .last60: (.downloadLast60, .uploadLast60)
            case .today, .mobileToday: (.downloadToday, .uploadToday)
            }
            if item.networkSource == .mobileToday { return (.mobileUsed, nil) }
            switch item.networkDirection {
            case .download: return (down, nil)
            case .upload: return (up, nil)
            case .both: return item.style == .networkChart ? (down, up) : (up, down)
            }
        }
    }

    private static func legacyVisual(_ item: MenuBarItemConfig, hasSecondary: Bool) -> ComponentVisual {
        switch item.style {
        case .text, .speedOneLine: .text
        case .stacked, .speedTwoLine: .stacked2
        case .verticalBar: .bar
        case .horizontalBar: .hbar
        case .ring: .ring
        case .sparkline, .networkChart: .sparkline
        case .dot: .dot
        case .iconValue: .iconValue
        }
    }
}
