import SwiftUI

extension OverviewTile {
    /// Abonelik limitleri karosu: en kritik pencere (en yüksek kullanım). Ajanlar kapalıysa yalnızca Codex verisi sayılır;
    /// hiç veri yoksa ve ajanlar kapalıysa karo gizlenir (nil). Karoya tıklayınca (veri olsun olmasın) Limitler ayrıntı sayfası açılır.
    static func limits(providers: [ProviderLimits], claudeConnected: Bool, agentsEnabled: Bool, thresholds: LimitAlertThresholds,
                       now: Date, forecast: (ProviderLimits, LimitWindowKind) -> LimitForecast?) -> OverviewTile? {
        let shown = providers.filter { agentsEnabled || $0.source != .claude }
        guard !shown.isEmpty else {
            guard agentsEnabled else { return nil }
            return OverviewTile(kind: .limits, title: "Limitler", symbol: "gauge.with.dots.needle.50percent",
                                value: claudeConnected ? "Bekleniyor" : "Bağlı değil",
                                secondary: claudeConnected ? "Claude'dan veri gelince" : "Claude limitlerini bağla",
                                help: claudeConnected
                                    ? "Claude limitleri bağlı; Claude Code ilk yanıtını verince değerler görünür."
                                    : "Claude 5 saatlik ve haftalık limitlerini görmek için tıklayıp Ayarlar'dan bağlayın.",
                                tint: .secondary, accessory: .bar(0), opensDetail: true)
        }

        struct Entry { var provider: ProviderLimits; var kind: LimitWindowKind; var window: LimitWindow; var stale: Bool }
        let entries = shown.flatMap { provider in
            LimitWindowKind.allCases.compactMap { kind -> Entry? in
                guard let window = provider.window(kind), !window.isReset(now: now) else { return nil }
                return Entry(provider: provider, kind: kind, window: window, stale: provider.isStale(now: now))
            }
        }
        let pool = entries.contains { !$0.stale } ? entries.filter { !$0.stale } : entries
        let help = helpLines(shown, thresholds: thresholds, now: now, forecast: forecast).joined(separator: "\n")
        guard let top = pool.max(by: { $0.window.usedPercent < $1.window.usedPercent }) else {
            return OverviewTile(kind: .limits, title: "Limitler", symbol: "gauge.with.dots.needle.50percent",
                                value: "\(shown[0].source.displayName) —", secondary: "Pencere yenilendi", help: help,
                                tint: .secondary, accessory: .bar(0), opensDetail: true)
        }

        let name = top.provider.source.displayName
        let level = thresholds.level(for: top.window.usedPercent, kind: top.kind)
        let tint: Color = top.stale ? .secondary : (level == .critical ? .red : (level == .warning ? .orange : .accentColor))
        var secondary = shortLabel(top.kind)
        var secondaryTint: Color?
        if top.stale {
            secondary = "Son veri \(LimitFormat.ageText(top.provider.observedAt, now: now))"
        } else if let fill = forecast(top.provider, top.kind) {
            secondary = "~\(LimitForecastFormat.moment(fill.fillsAt, kind: top.kind, now: now))\(LimitForecastFormat.locativeSuffix(fill.fillsAt)) dolar"
            secondaryTint = .orange
        } else if let resetsAt = top.window.resetsAt {
            secondary += " · \(LimitForecastFormat.moment(resetsAt, kind: top.kind, now: now))\(LimitForecastFormat.locativeSuffix(resetsAt)) yenilenir"
        }
        return OverviewTile(kind: .limits, title: "Limitler", symbol: "gauge.with.dots.needle.50percent",
                            value: "\(name) \(LimitFormat.percent(top.window.usedPercent))", secondary: secondary, help: help,
                            tint: tint, accessory: .bar(top.window.usedPercent / 100), secondaryTint: secondaryTint, opensDetail: true)
    }

    private static func shortLabel(_ kind: LimitWindowKind) -> String { kind == .fiveHour ? "5 sa" : "Haftalık" }

    private static func helpLines(_ providers: [ProviderLimits], thresholds: LimitAlertThresholds, now: Date,
                                  forecast: (ProviderLimits, LimitWindowKind) -> LimitForecast?) -> [String] {
        providers.flatMap { provider -> [String] in
            let stale = provider.isStale(now: now)
            return LimitWindowKind.allCases.compactMap { kind -> String? in
                guard let window = provider.window(kind) else { return nil }
                var line = "\(provider.source.displayName) \(kind.label): "
                if window.isReset(now: now) { return line + "yenilendi, yeni değer bekleniyor" }
                line += LimitFormat.percent(window.usedPercent)
                if let resetsAt = window.resetsAt {
                    line += " · \(LimitForecastFormat.moment(resetsAt, kind: kind, now: now))\(LimitForecastFormat.locativeSuffix(resetsAt)) yenilenir"
                }
                if stale { line += " · son veri \(LimitFormat.ageText(provider.observedAt, now: now))" }
                else if let fill = forecast(provider, kind) { line += " · " + LimitForecastFormat.cardLine(fill, kind: kind, now: now) }
                return line
            }
        }
    }
}
