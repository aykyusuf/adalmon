import Foundation

/// Everything that changes the rendered pixels; the status item is redrawn only when this changes.
struct MenuBarRenderKey: Equatable {
    var config: MenuBarConfig
    var components: [MenuBarComponent]
    var texts: [String]
    var levels: [Int]
    var connection: ConnectionState
    var histories: [[Int]]
    var battery: BatteryGlyphState?

    init(components: [MenuBarComponent], config: MenuBarConfig, values: WidgetValues) {
        self.config = config
        self.components = components
        connection = values.connection
        battery = components.contains { $0.fields.contains(.batteryLevel) } ? values.battery : nil
        var texts: [String] = []
        var levels: [Int] = []
        var histories: [[Int]] = []
        for c in components {
            for field in c.fields {
                texts.append(field.text(values, showUnits: config.showUnits, unit: c.unit))
                levels.append(Int((field.level(values) * 100).rounded()))
                if c.visual == .sparkline {
                    histories.append(Self.quantized(field.history(values)))
                }
            }
        }
        self.texts = texts
        self.levels = levels
        self.histories = histories
    }

    private static func quantized(_ values: [Double]) -> [Int] {
        let top = max(values.max() ?? 0, 0.000_001)
        return values.map { Int(($0 / top * 32).rounded()) }
    }
}
