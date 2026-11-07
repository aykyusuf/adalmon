import SwiftUI

/// Cihazlar sekmesindeki cihaz kartı: halka, ad, ayrıntı, uyarı / sabitle / gizle.
struct DeviceCard: View {
    let device: DeviceBattery
    @Binding var settings: DeviceSettings
    let isPinned: Bool
    let onPin: (Bool) -> Void
    var onPreview: (BatteryAlertEvent) -> Void = { _ in }
    @State private var showAlerts = false

    var body: some View {
        HStack(spacing: 14) {
            DeviceRing(device: device, size: 58, lineWidth: 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.name).font(.headline).lineLimit(1)
                    if device.isCharging { Image(systemName: "bolt.fill").foregroundStyle(.green) }
                }
                if device.hasPodBreakdown {
                    PodLevels(device: device, compact: false)
                } else {
                    Text(device.kind.title).font(.callout).foregroundStyle(.secondary)
                }
                Text(statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(device.levelText)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(device.isApproximate ? Color.secondary : DevicePalette.tint(device))
                .contentTransition(.numericText())
            HStack(spacing: 2) {
                actionButton(settings.alertEnabled ? "bell.fill" : "bell.slash", settings.alertEnabled ? "Uyarıları düzenle" : "Uyarılar kapalı",
                             tint: settings.alertEnabled ? .accentColor : .secondary) { showAlerts.toggle() }
                    .popover(isPresented: $showAlerts, arrowEdge: .bottom) {
                        DeviceAlertPopover(name: device.name, settings: $settings, onPreview: onPreview)
                    }
                actionButton(isPinned ? "pin.fill" : "pin", isPinned ? "Menü çubuğundan kaldır" : "Menü çubuğuna sabitle",
                             tint: isPinned ? .accentColor : .secondary) { onPin(!isPinned) }
                actionButton("eye.slash", "Gizle", tint: .secondary) { settings.hidden = true }
            }
        }
        .batteryCard(padding: 14)
        .opacity(device.isStale && !device.isConnected ? 0.8 : 1)
        .accessibilityElement(children: .contain)
    }

    private var statusLine: String {
        var parts: [String] = []
        parts.append(device.isConnected ? "Bağlı" : "Son görülme: " + device.lastSeenText())
        if device.isApproximate { parts.append("~ yaklaşık") }
        if let s = device.sources.first { parts.append(s.title) }
        return parts.joined(separator: " · ")
    }

    private func actionButton(_ symbol: String, _ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(label, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .help(label)
    }
}
