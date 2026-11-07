import SwiftUI

/// Menü çubuğu panelindeki "Pil" kartı: büyük yüzde, durum, dilimli çubuk, sağlık/döngü/sıcaklık, güç akışı, mAh, enerji yiyenler.
struct BatteryPanelSection: View {
    let data: PanelData
    @Binding var config: PanelConfig
    @Environment(\.panelDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if data.battery != nil || !data.devices.isEmpty {
            let collapsed = config.isCollapsed(.battery)
            let r = data.battery
            VStack(alignment: .leading, spacing: 6) {
                PanelSectionHeader(title: r == nil ? "Cihazlar" : "Pil", isCollapsed: collapsed) {
                    withAnimation(.panel(reduceMotion: reduceMotion)) { config.toggleCollapsed(.battery) }
                } accessory: {
                    if let r {
                        Text(collapsed ? "%\(r.level) · " + BatteryFormat.statusLine(r) : "Sağlık " + BatteryFormat.percent(r.primaryHealthPercent))
                    } else {
                        Text("\(data.devices.count) cihaz")
                    }
                }
                if !collapsed {
                    VStack(alignment: .leading, spacing: 8) {
                        if let r {
                            let tint = BatteryPalette.tint(r)
                            topRow(r, tint)
                            SegmentedCapacityBar(level: r.level, tint: tint, charging: r.isCharging, segments: 20, height: 8)
                            statRow(r)
                            flowRow(r)
                            capacityRow(r)
                            if !data.batteryApps.isEmpty { appsRow }
                        }
                        if !data.devices.isEmpty {
                            if r != nil { Divider().opacity(0.5) }
                            DevicePanelList(devices: data.devices)
                        }
                    }
                    .padding(density.cardPadding + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { PanelCardBackground(cornerRadius: PanelMetricCard.cornerRadius) }
                    .transition(.opacity)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func topRow(_ r: BatteryReading, _ tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("%\(r.level)")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if r.isCharging { Image(systemName: "bolt.fill").foregroundStyle(tint).font(.callout) }
            Spacer(minLength: 4)
            Text(BatteryFormat.statusLine(r))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func statRow(_ r: BatteryReading) -> some View {
        HStack(spacing: 6) {
            stat("heart.fill", "Sağlık", BatteryFormat.percent(r.primaryHealthPercent),
                 r.rawHealthPercent.map { "ham %\($0)" }, BatteryPalette.healthTint(r.primaryHealthPercent))
            stat("arrow.triangle.2.circlepath", "Döngü", BatteryFormat.int(r.cycles), "/ \(BatteryFormat.int(r.cycleLimit))", .blue)
            stat("thermometer.medium", "Sıcaklık", r.temperatureC.map { BatteryFormat.temp($0).replacingOccurrences(of: " °C", with: "°") } ?? "—",
                 BatteryFormat.temperatureStatus(r.temperatureC)?.title, BatteryPalette.tempTint(r.temperatureC))
        }
    }

    private func stat(_ symbol: String, _ title: String, _ value: String, _ note: String?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(title, systemImage: symbol).labelStyle(PanelTitleLabelStyle(tint: tint)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(.callout, design: .rounded, weight: .semibold)).monospacedDigit()
            Text(note ?? " ").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func flowRow(_ r: BatteryReading) -> some View {
        let f = PowerFlowSummary(r)
        HStack(spacing: 6) {
            if r.isPluggedIn {
                Image(systemName: r.cable == .magSafe ? "magsafe.batterypack" : "powerplug.fill").foregroundStyle(.green)
                Text("\(f.adapterWatts) \(f.cableTitle)").fontWeight(.medium)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                Text("Mac \(f.macWatts)").fontWeight(.medium)
                if let rate = r.chargeRateW, rate > 0.05 {
                    Text("· şarja \(BatteryFormat.watts(rate))").foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "laptopcomputer").foregroundStyle(.secondary)
                Text("Mac çekiyor \(f.macWatts)").fontWeight(.medium)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private func capacityRow(_ r: BatteryReading) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.batteryblock").foregroundStyle(.tertiary)
            Text("\(BatteryFormat.int(r.rawCurrentMAh)) / \(BatteryFormat.int(r.rawMaxMAh)) mAh")
            Text("· tasarım \(BatteryFormat.int(r.designMAh))").foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .help("Kalan / tam dolu (ham) / tasarım kapasitesi. Sağlık: Apple'ın “Maksimum kapasite” değeri; ham oran = tam dolu ÷ tasarım.")
    }

    private var appsRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("En çok enerji yiyenler · 24 sa").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(data.batteryApps.prefix(3)) { app in
                HStack(spacing: 6) {
                    Text(app.name).font(.caption).lineLimit(1)
                    Spacer(minLength: 4)
                    UsageBar(fraction: app.share, tint: .orange, height: 4).frame(width: 70)
                    Text(Format.percent(app.share)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}
