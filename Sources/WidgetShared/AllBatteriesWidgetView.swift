import SwiftUI

/// "Tüm piller": halkalar / liste / çubuklar.
struct AllBatteriesWidgetView: View {
    var snapshot: WidgetSnapshot
    var options: WidgetBatteryOptions
    var size: WidgetSize
    var now: Date = .now

    private var palette: WidgetTint { WidgetTint(appearance: options.appearance) }
    private var stale: Bool { snapshot.isStale(at: now) }

    var body: some View {
        let all = options.items(from: snapshot)
        let capacity = options.capacity(for: size)
        let shown = Array(all.prefix(capacity))
        let hidden = all.count - shown.count
        VStack(spacing: 6) {
            if shown.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "battery.0percent").font(.system(size: 24)).foregroundStyle(.secondary)
                    Text(options.emptyHint(snapshot: snapshot)).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content(shown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size == .large && options.style != .rings ? .top : .center)
                    .opacity(stale ? 0.45 : 1)
            }
            if hidden > 0 && !stale && size != .small {
                Text("+\(hidden) daha").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            if stale { WidgetStaleNote() }
        }
        .padding(size == .small ? 12 : 14)
    }

    @ViewBuilder private func content(_ items: [WidgetBatteryItem]) -> some View {
        let grid = WidgetBatteryOptions.grid(style: options.style, size: size)
        switch options.style {
        case .rings:
            let rows = chunk(items, by: grid.columns)
            VStack(spacing: size == .small ? 6 : (size == .medium ? 8 : 26)) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(rows[r]) { ringCell($0).frame(maxWidth: .infinity) }
                        // Boş hücreler: son satır hizası bozulmasın.
                        ForEach(0..<(grid.columns - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                    }
                }
            }
        case .list, .bars:
            let columns = (0..<grid.columns).map { c in items.enumerated().filter { $0.offset % grid.columns == c }.map(\.element) }
            HStack(alignment: .top, spacing: 14) {
                ForEach(columns.indices, id: \.self) { c in
                    VStack(spacing: options.style == .list ? (size == .large ? 10 : 6) : (size == .large ? 18 : 8)) {
                        ForEach(columns[c]) { row($0) }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder private func row(_ item: WidgetBatteryItem) -> some View {
        if options.style == .list { listRow(item) } else { barRow(item) }
    }

    private func chunk(_ items: [WidgetBatteryItem], by n: Int) -> [[WidgetBatteryItem]] {
        stride(from: 0, to: items.count, by: max(1, n)).map { Array(items[$0..<min($0 + n, items.count)]) }
    }

    private var ringDiameter: CGFloat { size == .small ? 36 : (size == .medium ? (stale ? 28 : 34) : 62) }

    private func ringCell(_ item: WidgetBatteryItem) -> some View {
        let color = palette.battery(level: item.level, charging: item.isCharging)
        return VStack(spacing: 3) {
            WidgetRing(fraction: item.fraction, color: color, lineWidth: size == .large ? 7 : (size == .small ? 4 : 5)) {
                Image(systemName: item.symbol)
                    .font(.system(size: ringDiameter * 0.36, weight: .medium))
                    .foregroundStyle(item.isConnected ? .primary : .secondary)
            }
            .frame(width: ringDiameter, height: ringDiameter)
            HStack(spacing: 1) {
                if item.isCharging { Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(color) }
                Text(item.levelText).font(.system(size: size == .small ? 11.5 : 13, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            if options.showNames {
                Text(item.name).font(.system(size: size == .small ? 9 : 9.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
        }
        .opacity(item.isConnected ? 1 : 0.6)
        .modifier(BatteryItemAccessibility(item: item))
    }

    private func listRow(_ item: WidgetBatteryItem) -> some View {
        let color = palette.battery(level: item.level, charging: item.isCharging)
        return HStack(spacing: 7) {
            Image(systemName: item.symbol).font(.system(size: 13, weight: .medium)).frame(width: 18)
                .foregroundStyle(item.isConnected ? .primary : .secondary)
            if options.showNames {
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 2)
            } else {
                WidgetBar(fraction: item.fraction, color: color, height: 5)
            }
            if item.isCharging { Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(color) }
            Text(item.levelText).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color == .primary ? .primary : color)
        }
        .frame(height: size == .large ? 36 : 26)
        .opacity(item.isConnected ? 1 : 0.6)
        .modifier(BatteryItemAccessibility(item: item))
    }

    private func barRow(_ item: WidgetBatteryItem) -> some View {
        let color = palette.battery(level: item.level, charging: item.isCharging)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: item.symbol).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(item.isConnected ? .primary : .secondary)
                if options.showNames {
                    Text(item.name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 2)
                if item.isCharging { Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(color) }
                Text(item.levelText).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            WidgetBar(fraction: item.fraction, color: color, height: size == .large ? 11 : 7)
        }
        .opacity(item.isConnected ? 1 : 0.6)
        .modifier(BatteryItemAccessibility(item: item))
    }
}

/// Ekran okuyucu için tek öğe: "iPhone, yüzde 79, şarj oluyor".
private struct BatteryItemAccessibility: ViewModifier {
    let item: WidgetBatteryItem

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
            .accessibilityValue((item.level.map { "yüzde \($0)" } ?? "bilinmiyor") + (item.isCharging ? ", şarj oluyor" : "") + (item.isConnected ? "" : ", bağlı değil"))
    }
}
