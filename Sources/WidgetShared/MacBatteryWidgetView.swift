import SwiftUI

/// "Mac pili": büyük yüzde, kalan süre, sağlık.
struct MacBatteryWidgetView: View {
    var snapshot: WidgetSnapshot
    var size: WidgetSize
    var appearance: WidgetAppearance = .color
    var now: Date = .now

    private var palette: WidgetTint { WidgetTint(appearance: appearance) }
    private var stale: Bool { snapshot.isStale(at: now) }

    var body: some View {
        VStack(spacing: 6) {
            if let mac = snapshot.mac {
                Group {
                    switch size {
                    case .small: small(mac)
                    case .medium: medium(mac)
                    case .large: large(mac)
                    }
                }
                .opacity(stale ? 0.45 : 1)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "desktopcomputer").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Bu Mac'te pil yok").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if stale { WidgetStaleNote() }
        }
        .padding(size == .small ? 12 : 16)
    }

    private func color(_ mac: WidgetSnapshot.MacEntry) -> Color { palette.battery(level: mac.level, charging: mac.isCharging) }

    private func header(_ mac: WidgetSnapshot.MacEntry) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "laptopcomputer").font(.system(size: 12, weight: .semibold))
            Text("Bu Mac").font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            if mac.lowPowerMode { Image(systemName: "powersleep").font(.system(size: 11)).foregroundStyle(palette.tint(.yellow)) }
            if mac.isCharging { Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(color(mac)) }
        }
        .foregroundStyle(.secondary)
    }

    private func bigPercent(_ mac: WidgetSnapshot.MacEntry, font: CGFloat) -> some View {
        Text("%\(mac.level)").font(.system(size: font, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(color(mac) == .primary ? .primary : color(mac)).minimumScaleFactor(0.7).lineLimit(1)
    }

    private func small(_ mac: WidgetSnapshot.MacEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(mac)
            Spacer(minLength: 0)
            bigPercent(mac, font: 44)
            WidgetBar(fraction: Double(mac.level) / 100, color: color(mac), height: 7)
            Text(WidgetFormat.macStatus(mac)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func detailRows(_ mac: WidgetSnapshot.MacEntry, full: Bool) -> [(String, String, String)] {
        var rows: [(String, String, String)] = [
            ("heart.fill", "Sağlık", mac.healthPercent.map { "%\($0)" } ?? "—"),
            ("arrow.triangle.2.circlepath", "Döngü", mac.cycles.map { "\($0)" + (mac.cycleLimit.map { " / \($0)" } ?? "") } ?? "—"),
        ]
        rows.append(("thermometer.medium", "Sıcaklık", mac.temperatureC.map { WidgetFormat.number($0, digits: 1) + " °C" } ?? "—"))
        if full || mac.isCharging {
            let power = mac.adapterWatts.map { "\($0) W adaptör" } ?? mac.powerW.map { WidgetFormat.number(abs($0), digits: 1) + " W" } ?? "—"
            rows.append(("powerplug.fill", "Güç", power))
        }
        return rows
    }

    private func medium(_ mac: WidgetSnapshot.MacEntry) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                header(mac)
                Spacer(minLength: 0)
                bigPercent(mac, font: 50)
                WidgetBar(fraction: Double(mac.level) / 100, color: color(mac), height: 8)
                Text(WidgetFormat.macStatus(mac)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            VStack(alignment: .leading, spacing: 9) {
                Spacer(minLength: 0)
                ForEach(detailRows(mac, full: false), id: \.1) { row in
                    HStack(spacing: 6) {
                        Image(systemName: row.0).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 14)
                        Text(row.1).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 2)
                        Text(row.2).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 140)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func large(_ mac: WidgetSnapshot.MacEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(mac)
            Spacer(minLength: 8)
            HStack(spacing: 20) {
                WidgetRing(fraction: Double(mac.level) / 100, color: color(mac), lineWidth: 13) {
                    VStack(spacing: 0) {
                        bigPercent(mac, font: 40)
                        Text(WidgetFormat.macShortState(mac)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 8) {
                    Text(WidgetFormat.macStatus(mac)).font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.8)
                    ForEach(detailRows(mac, full: true), id: \.1) { row in
                        HStack(spacing: 6) {
                            Image(systemName: row.0).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 14)
                            Text(row.1).font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer(minLength: 2)
                            Text(row.2).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Divider()
            Spacer(minLength: 8)
            let devices = snapshot.devices.filter { $0.level != nil }.prefix(4)
            if devices.isEmpty {
                Text("Bağlı aksesuar pili yok").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(devices)) { d in
                        VStack(spacing: 4) {
                            WidgetRing(fraction: Double(d.level ?? 0) / 100, color: palette.battery(level: d.level, charging: d.isCharging), lineWidth: 4) {
                                Image(systemName: d.symbol).font(.system(size: 13)).foregroundStyle(d.isConnected ? .primary : .secondary)
                            }
                            .frame(width: 40, height: 40)
                            Text("%\(d.level ?? 0)").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(d.name).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
