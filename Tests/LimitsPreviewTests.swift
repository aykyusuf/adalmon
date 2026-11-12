import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Limit kartı (Genel bakış), Limitler sayfası (kenar çubuğu) ve panel kartını sahte veriyle ekran dışında çizip PNG yazar (açık + koyu).
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class LimitsPreviewTests: XCTestCase {
    private let now = Date()

    private func window(_ used: Double, resetsIn: TimeInterval) -> LimitWindow {
        LimitWindow(usedPercent: used, resetsAt: now.addingTimeInterval(resetsIn))
    }

    /// Claude %62 / %35 (5 sa için dolma tahmini), Codex %97 kritik / %80 uyarı.
    private var mixed: [ProviderLimits] {
        [ProviderLimits(source: .claude, fiveHour: window(62, resetsIn: 2 * 3600 + 10 * 60), weekly: window(35, resetsIn: 3 * 86_400 + 4 * 3600), observedAt: now.addingTimeInterval(-90)),
         ProviderLimits(source: .codex, fiveHour: window(97, resetsIn: 75 * 60), weekly: window(80, resetsIn: 86_400 + 5 * 3600), observedAt: now.addingTimeInterval(-240), creditsBalance: 12.5)]
    }

    /// Claude bayat (3 sa önce), Codex yok.
    private var stale: [ProviderLimits] {
        [ProviderLimits(source: .claude, fiveHour: window(62, resetsIn: 2 * 3600), weekly: window(35, resetsIn: 3 * 86_400), observedAt: now.addingTimeInterval(-3 * 3600))]
    }

    /// Claude bağlı değil, Codex bayat.
    private var codexStaleOnly: [ProviderLimits] {
        [ProviderLimits(source: .codex, fiveHour: window(80, resetsIn: 3600), weekly: window(46, resetsIn: 2 * 86_400), observedAt: now.addingTimeInterval(-5 * 3600))]
    }

    /// Codex 5 saatlik %100 dolu, son veri 52 dk önce; Claude taze.
    private var codexFullStale: [ProviderLimits] {
        [ProviderLimits(source: .claude, fiveHour: window(62, resetsIn: 2 * 3600 + 10 * 60), weekly: window(35, resetsIn: 3 * 86_400), observedAt: now.addingTimeInterval(-90)),
         ProviderLimits(source: .codex, fiveHour: window(100, resetsIn: 2 * 3600 + 8 * 60), weekly: window(46, resetsIn: 2 * 86_400), observedAt: now.addingTimeInterval(-52 * 60))]
    }

    /// Claude Ultra: yalnızca haftalık pencere (5 saatlik yok), Codex tam.
    private var weeklyOnly: [ProviderLimits] {
        [ProviderLimits(source: .claude, fiveHour: nil, weekly: window(58, resetsIn: 3 * 86_400 + 4 * 3600), observedAt: now.addingTimeInterval(-90)),
         ProviderLimits(source: .codex, fiveHour: window(42, resetsIn: 3 * 3600), weekly: window(31, resetsIn: 2 * 86_400), observedAt: now.addingTimeInterval(-240))]
    }

    /// Sahte model dağılımı: Claude yalnızca haftalık, Codex her iki pencere.
    private func fakeUsage(_ providers: [ProviderLimits]) -> [LimitSource: ProviderModelUsage] {
        var result: [LimitSource: ProviderModelUsage] = [:]
        for provider in providers {
            let ranges = ModelUsageBuilder.ranges(for: provider, now: now)
            let models: [ModelAggregate] = provider.source == .claude
                ? [ModelAggregate(model: "claude-opus-5-5", tokens: ModelTokens(input: 2_900, output: 10_800_000, cacheWrite: 49_300_000, cacheRead: 2_605_000_000), messages: 12_340),
                   ModelAggregate(model: "claude-sonnet-5-5", tokens: ModelTokens(input: 2_400, output: 13_400_000, cacheWrite: 59_100_000, cacheRead: 2_060_000_000), messages: 11_760),
                   ModelAggregate(model: "claude-haiku-5-5", tokens: ModelTokens(input: 850, output: 237_000, cacheWrite: 2_700_000, cacheRead: 15_700_000), messages: 402)]
                : [ModelAggregate(model: "gpt-6.1-sol", tokens: ModelTokens(input: 3_470_000, output: 1_100_000, cacheWrite: 0, cacheRead: 275_000_000), messages: 1_769),
                   ModelAggregate(model: "gpt-6.1-terra", tokens: ModelTokens(input: 1_260_000, output: 131_000, cacheWrite: 0, cacheRead: 21_400_000), messages: 337)]
            result[provider.source] = ModelUsageBuilder.build(source: provider.source, ranges: ranges, now: now) { _, _ in models }
        }
        return result
    }

    private func fillForecast(_ provider: ProviderLimits, _ kind: LimitWindowKind) -> LimitForecast? {
        guard kind == .fiveHour, let window = provider.window(kind) else { return nil }
        let minutes: Double = provider.source == .claude ? 95 : 40
        return LimitForecast(fillsAt: now.addingTimeInterval(minutes * 60), resetsAt: window.resetsAt ?? now, ratePerHour: 14.5,
                             usedPercent: window.usedPercent, basedOn: now)
    }

    private func snapshot(_ providers: [ProviderLimits], connected: Bool, agents: Bool = true, usage: Bool = false) -> LimitsSnapshot {
        let thresholds = LimitAlertThresholds()
        var plans: [LimitSource: LimitPlan] = [:]
        if providers.contains(where: { $0.source == .claude }) {
            plans[.claude] = LimitPlanMapper.claude(ClaudeAccountPlan(planDisplayName: "Ultra", organizationType: "claude_max",
                                                                      rateLimitTier: "default_claude_max_20x", billingType: "stripe_subscription",
                                                                      hasExtraUsageEnabled: false))
        }
        if providers.contains(where: { $0.source == .codex }) { plans[.codex] = LimitPlanMapper.codex(planType: "plus") }
        return LimitsSnapshot(
            sections: LimitsPresentation.sections(providers: providers, claudeConnected: connected, agentsEnabled: agents, codexEnabled: true,
                                                  thresholds: thresholds, now: now, forecast: fillForecast),
            thresholds: thresholds, now: now, plans: plans, modelUsage: usage ? fakeUsage(providers) : [:])
    }

    private func tile(_ providers: [ProviderLimits], connected: Bool) -> OverviewTile? {
        OverviewTile.limits(providers: providers, claudeConnected: connected, agentsEnabled: true, thresholds: LimitAlertThresholds(),
                            now: now, forecast: fillForecast)
    }

    private func normalTile(_ title: String, _ value: String, _ secondary: String, fraction: Double) -> OverviewTile {
        OverviewTile(kind: .memory, title: title, symbol: "memorychip", value: value, secondary: secondary, help: "", tint: .green, accessory: .bar(fraction))
    }

    func testRenderLimitsViews() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scenarios: [(String, [ProviderLimits], Bool)] = [("mixed", mixed, true), ("stale", stale, true),
                                                              ("codexstale", codexStaleOnly, false), ("empty", [], false),
                                                              ("weeklyonly", weeklyOnly, true), ("codexfull", codexFullStale, true)]
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            // Genel bakış karosu: yanındaki normal karolarla aynı boyutta mı?
            for (name, providers, connected) in scenarios {
                let snap = snapshot(providers, connected: connected)
                let limitsTile = try XCTUnwrap(tile(providers, connected: connected))
                let row = HStack(spacing: 10) {
                    OverviewTileView(tile: normalTile("RAM", "9,4 GB", "6,6 GB boş", fraction: 0.58), action: {})
                    OverviewLimitsCardContent(tile: limitsTile, snapshot: snap, action: {})
                    OverviewTileView(tile: normalTile("Disk", "%71", "120 GB boş", fraction: 0.71), action: {})
                }
                .padding(16)
                .background(dark ? Color(white: 0.13) : Color(white: 0.96))
                try await render(row, name: "limits-card-\(name)-\(mode)", dir: dir, size: NSSize(width: 560, height: 130), dark: dark)
            }
            // Dar karo (minimum genişlik 138).
            let mixedTile = try XCTUnwrap(tile(mixed, connected: true))
            let narrow = HStack(spacing: 10) {
                OverviewTileView(tile: normalTile("RAM", "9,4 GB", "6,6 GB boş", fraction: 0.58), action: {}).frame(width: 138)
                OverviewLimitsCardContent(tile: mixedTile, snapshot: snapshot(mixed, connected: true), action: {}).frame(width: 138)
            }
            .padding(16)
            .background(dark ? Color(white: 0.13) : Color(white: 0.96))
            try await render(narrow, name: "limits-card-narrow-\(mode)", dir: dir, size: NSSize(width: 340, height: 130), dark: dark)
            // Sayfa (kenar çubuğu sayfası): geniş (1400 pt pencerenin içerik alanı) ve dar (940 pt pencere); eğimsiz, sabit eğimli ve giriş sonrası.
            for (name, providers, connected) in scenarios {
                let snap = snapshot(providers, connected: connected, usage: name == "weeklyonly" || name == "mixed")
                for (sizeName, size) in [("wide", NSSize(width: 1180, height: 1300)), ("narrow", NSSize(width: 720, height: 1500))] {
                    let page = LimitsPageContent(snapshot: snap, openSettings: {}, entrance: false)
                        .background(Color(nsColor: .windowBackgroundColor))
                    try await render(page, name: "limits-page-\(name)-\(sizeName)-\(mode)", dir: dir, size: size, dark: dark, wait: 0.4)
                }
            }
            // Not: hover eğimi (rotation3DEffect) NSHostingView.cacheDisplay / CALayer.render çıktısında yanlış konumlanır (dönen katman
            // sol üste düşer); bu yüzden eğimli poz önizlemesi alınmaz. Tilt3D yalnızca canlı pencerede gözle doğrulanır.
            let entering = LimitsPageContent(snapshot: snapshot(mixed, connected: true), openSettings: {})
                .background(Color(nsColor: .windowBackgroundColor))
            try await render(entering, name: "limits-page-entrance-\(mode)", dir: dir, size: NSSize(width: 1180, height: 900), dark: dark, wait: 2.2)
            // Logolar (büyük + küçük boyutlar).
            let logos = HStack(spacing: 28) {
                ForEach(LimitSource.allCases) { source in
                    HStack(spacing: 16) {
                        BrandLogo(source: source, size: 96)
                        BrandLogo(source: source, size: 46)
                        BrandLogo(source: source, size: 24)
                        BrandLogo(source: source, size: 12)
                    }
                }
            }
            .padding(24)
            .background(dark ? Color(white: 0.13) : Color(white: 0.96))
            try await render(logos, name: "limits-logos-\(mode)", dir: dir, size: NSSize(width: 640, height: 150), dark: dark, wait: 0.3)
            // Panel kartı (372 pt).
            for (name, providers, _) in scenarios where !providers.isEmpty {
                let card = SubscriptionLimitsContent(providers: providers, thresholds: LimitAlertThresholds(), now: now, forecast: fillForecast)
                    .padding(12)
                    .frame(width: PanelContent.width)
                    .background(dark ? Color(white: 0.13) : Color(white: 0.96))
                try await render(card, name: "limits-panel-\(name)-\(mode)", dir: dir, size: NSSize(width: PanelContent.width, height: 230), dark: dark)
            }
        }
    }

    private func render<V: View>(_ view: V, name: String, dir: URL, size: NSSize, dark: Bool, wait: Double = 1.6) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).preferredColorScheme(dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        // Giriş animasyonu (0,9 sn) bitsin; bekleme askıya alınmalı (RunLoop değil).
        try await Task.sleep(for: .seconds(wait))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = dir.appending(path: "\(name).png")
        try png.write(to: url)
        print("LIMITS_PREVIEW: \(url.path())")
        window.close()
    }
}
