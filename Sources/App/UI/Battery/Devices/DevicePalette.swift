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

    /// Menü çubuğu paneli ve öğesi: şarjda ya da %90+ yeşil, %10 altı kırmızı, %20 altı turuncu, aksi halde nötr.
    static func panelTint(_ d: DeviceBattery) -> Color {
        guard let level = d.summaryLevel else { return .secondary }
        if d.isStale && !d.isConnected { return .secondary }
        if d.isCharging { return .green }
        if level <= 10 { return .red }
        if level < 20 { return .orange }
        if level >= 90 { return .green }
        return Color.primary.opacity(0.78)
    }

    static func panelTint(level: Int?) -> Color {
        guard let level else { return .secondary }
        if level <= 10 { return .red }
        if level < 20 { return .orange }
        if level >= 90 { return .green }
        return Color.primary.opacity(0.78)
    }
}
