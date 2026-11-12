import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Limit kartı (Genel bakış), Limitler sayfası ve panel kartını sahte veriyle ekran dışında çizip PNG yazar (açık + koyu).
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

    private func fillForecast(_ provider: ProviderLimits, _ kind: LimitWindowKind) -> LimitForecast? {
        guard kind == .fiveHour, let window = provider.window(kind) else { return nil }
        let minutes: Double = provider.source == .claude ? 95 : 40
        return LimitForecast(fillsAt: now.addingTimeInterval(minutes * 60), resetsAt: window.resetsAt ?? now, ratePerHour: 14.5,
                             usedPercent: window.usedPercent, basedOn: now)
    }

    private func snapshot(_ providers: [ProviderLimits], connected: Bool, agents: Bool = true) -> LimitsSnapshot {
        let thresholds = LimitAlertThresholds()
        return LimitsSnapshot(
            sections: LimitsPresentation.sections(providers: providers, claudeConnected: connected, agentsEnabled: agents, codexEnabled: true,
                                                  thresholds: thresholds, now: now, forecast: fillForecast),
            thresholds: thresholds, now: now)
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
                                                              ("codexstale", codexStaleOnly, false), ("empty", [], false)]
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
            // Sayfa.
            for (name, providers, connected) in scenarios {
                let page = LimitsDetailContent(snapshot: snapshot(providers, connected: connected), onBack: {}, openSettings: {})
                    .background(Color(nsColor: .windowBackgroundColor))
                try await render(page, name: "limits-page-\(name)-\(mode)", dir: dir, size: NSSize(width: 900, height: 820), dark: dark)
            }
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

    private func render<V: View>(_ view: V, name: String, dir: URL, size: NSSize, dark: Bool) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).preferredColorScheme(dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        // Giriş animasyonu (0,9 sn) bitsin; bekleme askıya alınmalı (RunLoop değil).
        try await Task.sleep(for: .seconds(1.6))
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
