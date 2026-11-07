import SwiftUI

/// "Sistem": CPU / RAM / ağ ↓↑ mini kartlar.
struct SystemWidgetView: View {
    var snapshot: WidgetSnapshot
    var size: WidgetSize
    var appearance: WidgetAppearance = .color
    var now: Date = .now

    private var palette: WidgetTint { WidgetTint(appearance: appearance) }
    private var stale: Bool { snapshot.isStale(at: now) }

    var body: some View {
        VStack(spacing: 6) {
            if let s = snapshot.system {
                Group {
                    switch size {
                    case .small: grid(s, columns: 2, ring: 38)
                    case .medium: row(s)
                    case .large: large(s)
                    }
                }
                .opacity(stale ? 0.45 : 1)
            } else {
                WidgetNoDataView()
            }
            if stale { WidgetStaleNote() }
        }
        .padding(size == .small ? 12 : 16)
    }

    private func loadCell(_ title: String, value: Double, base: Color, ring: CGFloat) -> some View {
        let color = palette.load(value, base: base)
        return VStack(spacing: 4) {
            WidgetRing(fraction: value / 100, color: color, lineWidth: ring > 50 ? 8 : 5) {
                Text(WidgetFormat.percent(value)).font(.system(size: ring * 0.28, weight: .semibold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            .frame(width: ring, height: ring)
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func netCell(up: Bool, rate: Double, large: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: large ? 30 : 24)).foregroundStyle(palette.tint(up ? .orange : .blue))
            Text(WidgetFormat.rate(rate)).font(.system(size: large ? 13 : 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(up ? "Yükleme" : "İndirme").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func grid(_ s: WidgetSnapshot.SystemEntry, columns: Int, ring: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                loadCell("CPU", value: s.cpuPercent, base: .blue, ring: ring)
                loadCell("RAM", value: s.ramPercent, base: .purple, ring: ring)
            }
            HStack(spacing: 0) {
                netCell(up: false, rate: s.downBytesPerSec)
                netCell(up: true, rate: s.upBytesPerSec)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ s: WidgetSnapshot.SystemEntry) -> some View {
        HStack(spacing: 0) {
            loadCell("CPU", value: s.cpuPercent, base: .blue, ring: 58)
            loadCell("RAM", value: s.ramPercent, base: .purple, ring: 58)
            netCell(up: false, rate: s.downBytesPerSec)
            netCell(up: true, rate: s.upBytesPerSec)
        }
        .frame(maxHeight: .infinity)
    }

    private func large(_ s: WidgetSnapshot.SystemEntry) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                loadCell("CPU", value: s.cpuPercent, base: .blue, ring: 92)
                loadCell("RAM", value: s.ramPercent, base: .purple, ring: 92)
            }
            HStack(spacing: 0) {
                netCell(up: false, rate: s.downBytesPerSec, large: true)
                netCell(up: true, rate: s.upBytesPerSec, large: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label("Mobil veri bugün", systemImage: "antenna.radiowaves.left.and.right").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(WidgetFormat.bytes(s.mobileTodayBytes)) / \(WidgetFormat.bytes(s.dailyCapBytes))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                WidgetBar(fraction: s.dailyFraction, color: palette.quota(s.dailyFraction), height: 8)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// "Mobil kota": günlük (ve varsa dönemlik) kullanım.
struct MobileQuotaWidgetView: View {
    var snapshot: WidgetSnapshot
    var size: WidgetSize
    var appearance: WidgetAppearance = .color
    var now: Date = .now

    private var palette: WidgetTint { WidgetTint(appearance: appearance) }
    private var stale: Bool { snapshot.isStale(at: now) }

    var body: some View {
        VStack(spacing: 6) {
            if let s = snapshot.system {
                Group {
                    switch size {
                    case .small: small(s)
                    case .medium: medium(s)
                    case .large: large(s)
                    }
                }
                .opacity(stale ? 0.45 : 1)
            } else {
                WidgetNoDataView()
            }
            if stale { WidgetStaleNote() }
        }
        .padding(size == .small ? 12 : 16)
    }

    private func gauge(_ s: WidgetSnapshot.SystemEntry, diameter: CGFloat, line: CGFloat) -> some View {
        WidgetRing(fraction: s.dailyFraction, color: palette.quota(s.dailyFraction), lineWidth: line) {
            VStack(spacing: 0) {
                Text(WidgetFormat.percent(s.dailyFraction * 100)).font(.system(size: diameter * 0.24, weight: .bold, design: .rounded)).monospacedDigit()
                Text("bugün").font(.system(size: max(9, diameter * 0.12))).foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func usedLine(_ s: WidgetSnapshot.SystemEntry, font: CGFloat = 12) -> some View {
        Text("\(WidgetFormat.bytes(s.mobileTodayBytes)) / \(WidgetFormat.bytes(s.dailyCapBytes))")
            .font(.system(size: font, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
    }

    private func small(_ s: WidgetSnapshot.SystemEntry) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 11, weight: .semibold))
                Text("Mobil kota").font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            gauge(s, diameter: 84, line: 8)
            usedLine(s)
        }
        .frame(maxHeight: .infinity)
    }

    private func remaining(_ s: WidgetSnapshot.SystemEntry) -> String {
        s.dailyCapBytes > s.mobileTodayBytes ? WidgetFormat.bytes(s.dailyCapBytes - s.mobileTodayBytes) + " kaldı" : "Limit doldu"
    }

    private func details(_ s: WidgetSnapshot.SystemEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mobil kota").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            usedLine(s, font: 17)
            Text(remaining(s)).font(.system(size: 12)).foregroundStyle(.secondary)
            if let f = s.monthlyFraction, let used = s.cycleUsedBytes, let cap = s.monthlyCapBytes {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dönem: \(WidgetFormat.bytes(used)) / \(WidgetFormat.bytes(cap))").font(.system(size: 11)).foregroundStyle(.secondary)
                    WidgetBar(fraction: f, color: palette.quota(f), height: 6)
                }
            }
            if s.isOnMobile {
                Label("Şu an mobil veride", systemImage: "iphone.radiowaves.left.and.right").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.tint(.orange))
            }
        }
    }

    private func medium(_ s: WidgetSnapshot.SystemEntry) -> some View {
        HStack(spacing: 20) {
            gauge(s, diameter: 104, line: 10)
            details(s)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private func large(_ s: WidgetSnapshot.SystemEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 22) {
                gauge(s, diameter: 150, line: 14)
                details(s)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Divider()
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                miniStat("arrow.down.circle.fill", WidgetFormat.rate(s.downBytesPerSec), "İndirme", .blue)
                miniStat("arrow.up.circle.fill", WidgetFormat.rate(s.upBytesPerSec), "Yükleme", .orange)
                miniStat("calendar", s.cycleUsedBytes.map(WidgetFormat.bytes) ?? "—", "Bu dönem", .green)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private func miniStat(_ symbol: String, _ value: String, _ title: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(palette.tint(color))
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
