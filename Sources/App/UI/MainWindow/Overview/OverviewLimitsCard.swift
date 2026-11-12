import SwiftUI

/// Genel bakıştaki limit karosu: Claude ve Codex için 5 saat / haftalık mini halkalar. Diğer karolarla aynı boyutta;
/// tıklayınca Limitler ayrıntı sayfası açılır. Değer değişince halka ve sayı yumuşakça değişir, ilk görünüşte halkalar bir kez dolar.
/// Pil: zamanlayıcı yok (dakikalık TimelineView yalnızca görünürken); sürekli animasyon yok.
struct OverviewLimitsCard: View {
    let tile: OverviewTile
    let model: SubscriptionLimitsModel
    let agentsEnabled: Bool
    let action: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            OverviewLimitsCardContent(tile: tile, snapshot: model.snapshot(agentsEnabled: agentsEnabled, now: context.date), action: action)
        }
    }
}

struct OverviewLimitsCardContent: View {
    let tile: OverviewTile
    let snapshot: LimitsSnapshot
    let action: () -> Void
    var entrance = true
    @State private var hovering = false

    var body: some View {
        let shown = snapshot.sections.filter { $0.display != nil }
        let featured = snapshot.featured
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
                if shown.isEmpty {
                    emptyBody
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.source) { index, section in
                            if index > 0 { Spacer(minLength: 4) }
                            if let display = section.display {
                                ProviderRings(display: display, isFeatured: featured?.source == display.source, entrance: entrance)
                            }
                        }
                        if shown.count == 1 { Spacer(minLength: 0) }
                    }
                    .padding(.top, 1)
                    Text(LimitsPresentation.cardCaption(snapshot) ?? " ")
                        .font(.caption)
                        .foregroundStyle(featured?.window.forecast != nil ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.4), value: LimitsPresentation.cardCaption(snapshot))
                }
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

    /// Veri yokken: karonun kendi metni ("Bağlı değil" / "Bekleniyor") + ince boş halka.
    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tile.value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(tile.secondary.isEmpty ? " " : tile.secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            LimitBar(fraction: 0, height: 4, entrance: entrance).frame(height: 14)
        }
    }
}

/// Bir sağlayıcının iki mini halkası ve adı.
private struct ProviderRings: View {
    let display: LimitProviderDisplay
    let isFeatured: Bool
    let entrance: Bool

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                ForEach(LimitWindowKind.allCases) { kind in
                    if let window = display.window(kind) {
                        LimitRing(fraction: window.fraction, tone: window.tone, diameter: 28, lineWidth: 3.5, label: window.numberText,
                                  labelFont: .system(size: 9, weight: .bold, design: .rounded),
                                  entrance: entrance)
                    } else {
                        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 3.5).frame(width: 28, height: 28)
                    }
                }
            }
            HStack(spacing: 3) {
                Image(systemName: LimitStyle.symbol(display.source)).font(.system(size: 7, weight: .bold))
                Text(display.source.displayName).font(.system(size: 10, weight: isFeatured ? .semibold : .regular))
            }
            .foregroundStyle(isFeatured ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .lineLimit(1)
        }
        .opacity(display.isStale ? 0.55 : 1)
    }
}
