import SwiftUI

/// Özet karoları: dar pencerede iki (ya da daha çok) dengeli satıra sarar (6 karo → 3 + 3).
struct OverviewTileGrid: View {
    let tiles: [OverviewTile]
    let width: CGFloat
    let router: SettingsRouter
    var limits: SubscriptionLimitsModel? = nil
    var agentsEnabled = true
    /// Limit karosuna tıklayınca Limitler ayrıntı sayfasını açar.
    var openLimits: () -> Void = {}

    static let minTileWidth: CGFloat = 138
    static let spacing: CGFloat = 10

    /// Satır başına karo: sığan en çok sayı; sarıyorsa satırlar dengelenir.
    static func columns(count: Int, width: CGFloat) -> Int {
        guard count > 0 else { return 1 }
        let fit = max(1, Int((width + spacing) / (minTileWidth + spacing)))
        if fit >= count { return count }
        let rows = Int((Double(count) / Double(fit)).rounded(.up))
        return Int((Double(count) / Double(rows)).rounded(.up))
    }

    var body: some View {
        let count = Self.columns(count: tiles.count, width: width)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: count), spacing: Self.spacing) {
            ForEach(tiles) { tile in
                if tile.opensDetail, let limits {
                    OverviewLimitsCard(tile: tile, model: limits, agentsEnabled: agentsEnabled, action: openLimits)
                } else {
                    OverviewTileView(tile: tile) { tile.kind.destination.open(router) }
                }
            }
        }
    }
}

/// Tıklanabilir küçük özet karosu: başlık, büyük değer, tek satır ek bilgi, küçük grafik/çubuk.
struct OverviewTileView: View {
    let tile: OverviewTile
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Label(tile.title, systemImage: tile.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0)
                        .accessibilityHidden(true)
                }
                Text(tile.value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(tile.secondary.isEmpty ? " " : tile.secondary)
                    .font(.caption)
                    .foregroundStyle(tile.secondaryTint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                accessory
                    .frame(height: 14)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(hovering ? 0.09 : 0.05), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tile.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(tile.accessibilityHint)
    }

    @ViewBuilder private var accessory: some View {
        switch tile.accessory {
        case .none: Color.clear
        case .bar(let fraction): UsageBar(fraction: fraction, tint: tile.tint, height: 4).frame(maxHeight: .infinity)
        case .split(let mobile, let wifi): SplitCapsule(mobile: mobile, wifi: wifi).frame(maxHeight: .infinity)
        case .sparkline(let values): TileSparkline(values: values, tint: tile.tint)
        }
    }
}

/// Hafif çizgi grafik (Charts yok): son ~60 sn geçmişi, 0...1.
private struct TileSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(values.count - 1)
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: size.height * (1 - CGFloat(min(1, max(0, v)))))
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(tint.opacity(0.18)))
            context.stroke(line, with: .color(tint), lineWidth: 1.2)
        }
        .accessibilityHidden(true)
    }
}

/// İnce iki renkli çubuk: Mobil / Wi‑Fi payı.
private struct SplitCapsule: View {
    let mobile: UInt64
    let wifi: UInt64

    var body: some View {
        let total = Double(mobile &+ wifi)
        let mobileShare = total > 0 ? Double(mobile) / total : 0
        GeometryReader { geo in
            HStack(spacing: 0) {
                MediumStyle.wifiColor.frame(width: geo.size.width * (1 - mobileShare))
                MediumStyle.mobileColor
            }
        }
        .frame(height: 4)
        .background(Color.primary.opacity(0.1))
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }
}
