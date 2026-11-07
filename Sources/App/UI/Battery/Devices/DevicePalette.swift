import SwiftUI

enum DevicePalette {
    static func tint(_ d: DeviceBattery) -> Color {
        guard let level = d.summaryLevel else { return .secondary }
        if d.isStale && !d.isConnected { return .secondary }
        if d.isCharging { return .green }
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return .green
    }

    static func tint(level: Int?) -> Color {
        guard let level else { return .secondary }
        return level <= 10 ? .red : (level <= 20 ? .orange : .green)
    }
}
