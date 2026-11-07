import SwiftUI

/// Menü çubuğu panelindeki cihaz satırı: simge, ad, çubuk, yüzde (kulaklıkta L/R/kutu).
struct DevicePanelRow: View {
    let device: DeviceBattery

    var body: some View {
        HStack(spacing: 8) {
            DeviceRing(device: device, size: 26, lineWidth: 2.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(.caption.weight(.medium)).lineLimit(1)
                if device.hasPodBreakdown {
                    PodLevels(device: device)
                } else {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if device.isCharging { Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green) }
            UsageBar(fraction: Double(device.summaryLevel ?? 0) / 100, tint: DevicePalette.tint(device), height: 4).frame(width: 46)
            Text(device.levelText)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
                .foregroundStyle(device.isApproximate ? Color.secondary : Color.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(device.summaryLevel.map { "yüzde \($0)" } ?? "bilinmiyor")\(device.isApproximate ? ", yaklaşık" : "")")
        .help(device.isApproximate ? "~ yaklaşık değer · son görülme: \(device.lastSeenText())" : device.kind.title)
    }

    private var subtitle: String {
        if !device.isConnected { return "son görülme: " + device.lastSeenText() }
        if device.isCharging { return "Şarj oluyor" }
        return device.kind.title
    }
}
