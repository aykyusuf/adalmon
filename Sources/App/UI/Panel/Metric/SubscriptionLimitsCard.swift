import SwiftUI

/// Ajanlar panelinin üstündeki "Abonelik limitleri" kartı: Claude ve Codex için 5 saat / haftalık kullanılan yüzde ve yenilenme
/// süresi. Veri yoksa hiç çizilmez. Eski veri (30 dk+) soluk gösterilir ve yaşı yazılır. Geri sayım dakikada bir yenilenir.
struct SubscriptionLimitsCard: View {
    let model: SubscriptionLimitsModel

    var body: some View {
        let providers = model.providers
        Group {
            if !providers.isEmpty {
                TimelineView(.everyMinute) { context in
                    SubscriptionLimitsContent(providers: providers, thresholds: model.thresholds, now: context.date,
                                              forecast: { model.forecast(for: $0, $1, now: context.date) })
                }
            } else {
                // Veri yokken de bir görünüm olmalı: onAppear yoksa Codex hiç okunmaz.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .onAppear { model.addViewer() }
        .onDisappear { model.removeViewer() }
    }
}

struct SubscriptionLimitsContent: View {
    let providers: [ProviderLimits]
    let thresholds: LimitAlertThresholds
    let now: Date
    var forecast: (ProviderLimits, LimitWindowKind) -> LimitForecast? = { _, _ in nil }

    var body: some View {
        PanelCard(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                PanelGroupTitle(title: "Abonelik limitleri")
                ForEach(providers, id: \.source) { provider in
                    ProviderLimitsRows(provider: provider, thresholds: thresholds, now: now, forecast: forecast)
                }
            }
        }
    }
}

private struct ProviderLimitsRows: View {
    let provider: ProviderLimits
    let thresholds: LimitAlertThresholds
    let now: Date
    let forecast: (ProviderLimits, LimitWindowKind) -> LimitForecast?

    var body: some View {
        let stale = provider.isStale(now: now)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(provider.source.displayName).font(.callout.weight(.semibold))
                Spacer(minLength: 4)
                if stale {
                    Text("Son veri \(LimitFormat.ageText(provider.observedAt, now: now))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if let balance = provider.creditsBalance {
                    Text("Kredi: \(balance.formatted(.number.precision(.fractionLength(0...2))))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            ForEach(LimitWindowKind.allCases) { kind in
                if let window = provider.window(kind) {
                    LimitWindowRow(kind: kind, window: window, level: thresholds.level(for: window.usedPercent, kind: kind),
                                   stale: stale, now: now, forecast: window.isReset(now: now) ? nil : forecast(provider, kind))
                }
            }
        }
        .opacity(stale ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct LimitWindowRow: View {
    let kind: LimitWindowKind
    let window: LimitWindow
    let level: LimitLevel
    let stale: Bool
    let now: Date
    let forecast: LimitForecast?

    var body: some View {
        let reset = window.isReset(now: now)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(kind.label).font(.caption).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
                UsageBar(fraction: reset ? 0 : window.usedPercent / 100, tint: tint(reset: reset))
                Text(reset ? "—" : LimitFormat.percent(window.usedPercent))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(reset ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint(reset: false)))
                    .frame(width: 38, alignment: .trailing)
            }
            if let resetsAt = window.resetsAt {
                Text(reset ? "Pencere yenilendi; yeni değer bekleniyor" : LimitFormat.resetText(resetsAt, now: now))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.leading, 64)
            }
            if let forecast {
                Text(LimitForecastFormat.cardLine(forecast, kind: kind, now: now))
                    .font(.caption2).foregroundStyle(.orange)
                    .padding(.leading, 64)
            }
        }
    }

    private func tint(reset: Bool) -> Color {
        if reset || stale { return .secondary }
        return switch level {
        case .critical: .red
        case .warning: .orange
        case .normal: .accentColor
        }
    }
}
