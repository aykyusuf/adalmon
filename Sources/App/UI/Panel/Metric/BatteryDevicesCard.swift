import SwiftUI

/// "Bağlı cihazlar": simge, ad, yüzde, ince seviye çubuğu; her satırda menü çubuğuna ekle / çıkar iğnesi.
struct BatteryDevicesCard: View {
    let devices: [DeviceBattery]
    let pinnedIDs: Set<String>
    let isLoading: Bool
    let focusID: String?
    @Binding var config: PanelConfig
    let actions: PanelActions
    @State private var timedOut = false

    private var state: ListLoadState { .resolve(isLoading: isLoading, itemCount: devices.count, timedOut: timedOut) }

    var body: some View {
        if state != .empty {
            PanelCollapsibleCard(id: "battery.devices", title: "Bağlı cihazlar", symbol: "airpodspro", tint: .blue,
                                 config: $config, forceOpen: focusID != nil, contentPadding: 0) {
                if !devices.isEmpty { Text("\(devices.count)") }
            } content: {
                SkeletonSwap(isLoading: state == .loading) {
                    VStack(spacing: 0) {
                        ForEach(Array(devices.prefix(8).enumerated()), id: \.element.id) { index, device in
                            if index > 0 { Divider().opacity(0.45).padding(.leading, 50) }
                            PanelDeviceRow(device: device, isPinned: pinnedIDs.contains(device.id), isFocused: device.id == focusID) {
                                actions.setDevicePinned(device.id, device.name, !pinnedIDs.contains(device.id))
                            }
                            .id("device.\(device.id)")
                        }
                        if devices.count > 8 {
                            Text("+\(devices.count - 8) cihaz daha").font(.caption2).foregroundStyle(.tertiary).padding(.vertical, 6)
                        }
                    }
                } placeholder: {
                    VStack(spacing: 0) {
                        ForEach(0..<2, id: \.self) { index in
                            if index > 0 { Divider().opacity(0.45).padding(.leading, 50) }
                            PanelDeviceRow(device: .placeholder(index), isPinned: false, isFocused: false, isPlaceholder: true) {}
                        }
                    }
                }
            }
            .loadTimeout($timedOut)
        }
    }
}

/// Tek cihaz satırı. `isPlaceholder`: aynı yerleşim, soluk bloklar (iskelet).
struct PanelDeviceRow: View {
    let device: DeviceBattery
    let isPinned: Bool
    let isFocused: Bool
    var isPlaceholder = false
    let onTogglePin: () -> Void

    var body: some View {
        let tint = DevicePalette.panelTint(device)
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.name).font(.callout).lineLimit(1).modifier(SkeletonIf(active: isPlaceholder))
                    Spacer(minLength: 4)
                    if device.isCharging && !isPlaceholder { Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green) }
                    Text(device.percentText)
                        .font(.system(.callout, design: .rounded, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(isPlaceholder ? AnyShapeStyle(.clear) : (device.isApproximate ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint)))
                        .background { if isPlaceholder { RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.primary.opacity(0.13)) } }
                    pinButton
                }
                if isPlaceholder {
                    Capsule().fill(.primary.opacity(0.13)).frame(height: 3)
                } else {
                    UsageBar(fraction: Double(device.summaryLevel ?? 0) / 100, tint: tint, height: 3)
                }
                detail
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isFocused ? Color.accentColor.opacity(0.14) : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .help(device.isApproximate ? "~ yaklaşık değer · son görülme: \(device.lastSeenText())" : device.kind.title)
    }

    @ViewBuilder
    private var detail: some View {
        if isPlaceholder {
            EmptyView()
        } else if device.hasPodBreakdown {
            HStack(spacing: 5) {
                podText("L", device.left)
                Text("·").foregroundStyle(.tertiary)
                podText("R", device.right)
                if let c = device.caseLevel {
                    Text("·").foregroundStyle(.tertiary)
                    podText("Kutu", c)
                }
                if isPinned { pinnedTag }
            }
            .font(.caption2.weight(.medium)).monospacedDigit()
        } else if !device.isConnected {
            Text("son görülme: " + device.lastSeenText()).font(.caption2).foregroundStyle(.secondary)
        } else if isPinned {
            pinnedTag.font(.caption2)
        }
    }

    private var pinnedTag: some View {
        Label("Menü çubuğunda", systemImage: "menubar.rectangle").labelStyle(.titleAndIcon).foregroundStyle(.secondary)
    }

    private func podText(_ label: String, _ level: Int?) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(level.map { "\($0)%" } ?? "—").foregroundStyle(DevicePalette.panelTint(level: level))
        }
    }

    @ViewBuilder
    private var icon: some View {
        if isPlaceholder {
            Circle().fill(.primary.opacity(0.13)).frame(width: 28, height: 28)
        } else {
            Image(systemName: device.kind.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(device.isStale && !device.isConnected ? Color.secondary : Color.primary)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.07), in: .circle)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var pinButton: some View {
        if isPlaceholder {
            Color.clear.frame(width: 22, height: 22)
        } else {
            Button(isPinned ? "Menü çubuğundan çıkar" : "Menü çubuğuna ekle", systemImage: isPinned ? "pin.fill" : "pin", action: onTogglePin)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                .frame(width: 22, height: 22)
                .background(isPinned ? Color.accentColor.opacity(0.16) : .clear, in: .circle)
                .help(isPinned ? "Menü çubuğundan çıkar" : "Menü çubuğuna ekle")
        }
    }

    private var spoken: String {
        "\(device.name), \(device.summaryLevel.map { "yüzde \($0)" } ?? "bilinmiyor")\(device.isApproximate ? ", yaklaşık" : "")\(isPinned ? ", menü çubuğunda" : "")"
    }
}

extension DeviceBattery {
    static func placeholder(_ index: Int) -> DeviceBattery {
        DeviceBattery(id: "placeholder.\(index)", name: index == 0 ? "Cihaz adı burada" : "Başka cihaz", kind: .other, level: 50, lastSeen: .now)
    }
}
