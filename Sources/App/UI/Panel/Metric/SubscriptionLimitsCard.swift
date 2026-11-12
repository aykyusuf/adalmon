import SwiftUI

/// Ajanlar panelinin üstündeki "Abonelik limitleri" kartı: Claude ve Codex için 5 saat / haftalık kullanım halkaları, yenilenme süresi
/// ve dolma tahmini. Veri yoksa hiç çizilmez. Eski veri (30 dk+) soluk gösterilir ve yaşı yazılır. Geri sayım dakikada bir yenilenir
/// (yalnızca görünürken); halka/sayı yalnızca ilk görünüşte ve değer değişince animasyonlanır, sürekli animasyon yoktur.
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
    var entrance = true

    var body: some View {
        let sections = LimitsPresentation.sections(providers: providers, claudeConnected: true, agentsEnabled: true, codexEnabled: true,
                                                   thresholds: thresholds, now: now, forecast: forecast)
        PanelCard(padding: 10) {
            VStack(alignment: .leading, spacing: 10) {
                PanelGroupTitle(title: "Abonelik limitleri")
                ForEach(sections.compactMap(\.display)) { display in
                    ProviderLimitsRows(display: display, now: now, entrance: entrance)
                }
            }
        }
    }
}

private struct ProviderLimitsRows: View {
    let display: LimitProviderDisplay
    let now: Date
    let entrance: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                BrandLogo(source: display.source, size: 12)
                Text(display.source.displayName).font(.callout.weight(.semibold))
                Spacer(minLength: 4)
                if display.isStale {
                    Text("Son veri \(display.ageText(now: now))").font(.caption2).foregroundStyle(.tertiary)
                }
                if let balance = display.creditsBalance {
                    Text("Kredi: \(balance.formatted(.number.precision(.fractionLength(0...2))))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                // Verisi gelmeyen pencere gösterilmez; kalan hücre tüm genişliği kullanır.
                ForEach(display.windows) { window in
                    LimitWindowCell(window: window, now: now, entrance: entrance)
                }
            }
        }
        .opacity(display.isStale ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct LimitWindowCell: View {
    let window: LimitWindowDisplay
    let now: Date
    let entrance: Bool

    var body: some View {
        HStack(spacing: 8) {
            LimitRing(fraction: window.fraction, tone: window.tone, diameter: 38, lineWidth: 4.5, label: window.numberText,
                      labelFont: .system(size: 11, weight: .bold, design: .rounded), entrance: entrance)
            VStack(alignment: .leading, spacing: 1) {
                Text(window.kind.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.85)
                if let forecast = forecastLine {
                    Text(forecast)
                        .font(.caption2).foregroundStyle(.orange).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .animation(.smooth(duration: 0.4), value: window)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        if window.isReset { return "Yenilendi, değer bekleniyor" }
        if let countdown = window.countdownText(now: now) { return "\(countdown) sonra" }
        return "Yenilenme bilinmiyor"
    }

    /// "~15:40'ta dolar" (karttaki "bu hızla" öneki panelde yer kazanmak için atılır).
    private var forecastLine: String? {
        guard let forecast = window.forecast else { return nil }
        let moment = LimitForecastFormat.moment(forecast.fillsAt, kind: window.kind, now: now)
        return "~\(moment)\(LimitForecastFormat.locativeSuffix(forecast.fillsAt)) dolar"
    }
}
