import SwiftUI

/// AirPods: sol / sağ / kutu yüzdeleri ve şarj şimşekleri.
struct PodLevels: View {
    let device: DeviceBattery
    var compact = true

    var body: some View {
        HStack(spacing: compact ? 6 : 12) {
            chip("L", device.left, charging: device.leftCharging)
            chip("R", device.right, charging: device.rightCharging)
            chip(compact ? "K" : "Kutu", device.caseLevel, charging: device.caseCharging)
        }
        .font(compact ? .caption2 : .callout)
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func chip(_ label: String, _ level: Int?, charging: Bool) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(level.map { "%\($0)" } ?? "—").fontWeight(.medium).foregroundStyle(DevicePalette.tint(level: level))
            if charging { Image(systemName: "bolt.fill").foregroundStyle(.green).imageScale(.small) }
        }
    }

    private var spoken: String {
        func part(_ name: String, _ v: Int?) -> String { v.map { "\(name) yüzde \($0)" } ?? "\(name) bilinmiyor" }
        return [part("Sol", device.left), part("Sağ", device.right), part("Kutu", device.caseLevel)].joined(separator: ", ")
    }
}
