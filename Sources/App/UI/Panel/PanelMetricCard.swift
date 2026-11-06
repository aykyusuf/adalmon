import SwiftUI

/// Izgaradaki tek kart: başlık, büyük değer, ikinci satır ve mini grafik.
/// Dolgu cam üstüne cam konmaz; yalnızca `.quaternary` + metriğe göre çok hafif renk geçişi.
struct PanelMetricCard: View {
    static let cornerRadius: CGFloat = 12

    let card: PanelCardModel
    @Environment(\.panelDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(card.title, systemImage: card.kind.systemImage)
                .labelStyle(PanelTitleLabelStyle(tint: card.tint))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(card.value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(card.valueTint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                if !card.unit.isEmpty {
                    Text(card.unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(card.caption.isEmpty ? " " : card.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            graphic
                .frame(height: density.sparklineHeight)
        }
        .padding(density.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .fill(LinearGradient(colors: [card.tint.opacity(0.14), card.tint.opacity(0)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .contentShape(.rect(cornerRadius: Self.cornerRadius))
        .help(card.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
    }

    @ViewBuilder
    private var graphic: some View {
        if let fraction = card.fraction {
            UsageBar(fraction: fraction, tint: card.tint, height: 6)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 4)
        } else {
            PanelSparkline(values: card.history, tint: card.tint, scale: card.scale)
        }
    }
}
