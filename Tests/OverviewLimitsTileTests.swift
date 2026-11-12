import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// USAGE-03: Genel bakıştaki "Limitler" karosunun metni ve hedefi (sahte limit verisiyle).
@MainActor
final class OverviewLimitsTileTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let none: (ProviderLimits, LimitWindowKind) -> LimitForecast? = { _, _ in nil }

    private func claude(five: Double?, weekly: Double? = nil, observed: Date? = nil) -> ProviderLimits {
        ProviderLimits(source: .claude,
                       fiveHour: five.map { LimitWindow(usedPercent: $0, resetsAt: now.addingTimeInterval(2 * 3600)) },
                       weekly: weekly.map { LimitWindow(usedPercent: $0, resetsAt: now.addingTimeInterval(3 * 86400)) },
                       observedAt: observed ?? now)
    }

    private func tile(_ providers: [ProviderLimits], connected: Bool = true, agents: Bool = true,
                      forecast: ((ProviderLimits, LimitWindowKind) -> LimitForecast?)? = nil) -> OverviewTile? {
        OverviewTile.limits(providers: providers, claudeConnected: connected, agentsEnabled: agents,
                            thresholds: LimitAlertThresholds(), now: now, forecast: forecast ?? none)
    }

    func testPicksMostCriticalWindow() throws {
        let t = try XCTUnwrap(tile([claude(five: 62, weekly: 30)]))
        XCTAssertEqual(t.value, "Claude %62")
        XCTAssertTrue(t.secondary.hasPrefix("5 sa · "), t.secondary)
        XCTAssertTrue(t.secondary.hasSuffix(" yenilenir"), t.secondary)
        XCTAssertTrue(t.opensDetail)
        let weekly = try XCTUnwrap(tile([claude(five: 10, weekly: 80)]))
        XCTAssertEqual(weekly.value, "Claude %80")
        XCTAssertTrue(weekly.secondary.hasPrefix("Haftalık · "))
        XCTAssertEqual(t.help.split(separator: "\n").count, 2, "tüm pencereler ipucunda")
    }

    func testForecastReplacesResetTextInOrange() throws {
        let fill = LimitForecast(fillsAt: now.addingTimeInterval(3600), resetsAt: now.addingTimeInterval(7200), ratePerHour: 40,
                                 usedPercent: 62, basedOn: now)
        let t = try XCTUnwrap(tile([claude(five: 62)], forecast: { _, _ in fill }))
        XCTAssertTrue(t.secondary.hasPrefix("~") && t.secondary.hasSuffix(" dolar"), t.secondary)
        XCTAssertNotNil(t.secondaryTint)
        XCTAssertTrue(t.help.contains("bu hızla ~"))
    }

    func testNotConnectedAndHidden() throws {
        let t = try XCTUnwrap(tile([], connected: false))
        XCTAssertEqual(t.value, "Bağlı değil")
        XCTAssertTrue(t.opensDetail, "veri yokken de Limitler sayfası açılır (Bağla eylemi orada)")
        XCTAssertEqual(try XCTUnwrap(tile([], connected: true)).value, "Bekleniyor")
        XCTAssertNil(tile([], agents: false), "ajanlar kapalı ve veri yok: gizli")
        let codex = ProviderLimits(source: .codex, fiveHour: LimitWindow(usedPercent: 20, resetsAt: nil), weekly: nil, observedAt: now)
        XCTAssertEqual(try XCTUnwrap(tile([claude(five: 90), codex], agents: false)).value, "Codex %20", "ajanlar kapalıyken yalnız Codex")
    }

    func testStaleShowsAge() throws {
        let t = try XCTUnwrap(tile([claude(five: 50, observed: now.addingTimeInterval(-3 * 3600))]))
        XCTAssertTrue(t.secondary.hasPrefix("Son veri"), t.secondary)
    }

    func testDestinationOpensLimitsPage() {
        XCTAssertEqual(OverviewTileKind.limits.destination, OverviewDestination(section: .limits))
        let router = SettingsRouter(isDockModeOn: { true })
        OverviewTileKind.limits.destination.open(router)
        XCTAssertEqual(router.selectedMainSection, .limits)
        XCTAssertNotEqual(router.selectedSettingsSection, .agents, "Ayarlar'a gidilmez")
    }

    // MARK: Tıklama → ayrıntı sayfası (gerçek fare olayıyla)

    private func click(_ view: some View, size: NSSize, at point: NSPoint) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        // Pencere koordinatı: sol alt köşe başlangıç; `point` sol üstten verilir.
        let location = NSPoint(x: point.x, y: host.frame.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(300))
        window.close()
    }

    func testClickingLimitsTileOpensLimitsPage() async throws {
        let suite = "adalmon.limits.tile.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let temp = FileManager.default.temporaryDirectory.appending(path: "adalmon-limits-tile-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let binder = ClaudeStatusLineBinder(settingsURL: temp.appending(path: "claude/settings.json"),
                                            supportDirectory: temp.appending(path: "support", directoryHint: .isDirectory),
                                            configURL: temp.appending(path: "config.json"))
        let model = SubscriptionLimitsModel(defaults: defaults, binder: binder, codexReader: CodexRolloutReader(root: temp), live: false)
        let at = Date.now
        model.ingestClaude(ProviderLimits(source: .claude, fiveHour: LimitWindow(usedPercent: 62, resetsAt: at.addingTimeInterval(7_800)),
                                          weekly: LimitWindow(usedPercent: 35, resetsAt: at.addingTimeInterval(300_000)), observedAt: at), now: at)
        let limitsTile = try XCTUnwrap(OverviewTile.limits(providers: model.providers, claudeConnected: true, agentsEnabled: true,
                                                           thresholds: model.thresholds, now: at, forecast: { _, _ in nil }))
        let router = SettingsRouter(isDockModeOn: { true })
        router.selectedMainSection = .overview
        var opened = 0
        let grid = OverviewTileGrid(tiles: [limitsTile], width: 200, router: router, limits: model, agentsEnabled: true, openLimits: { OverviewTileKind.limits.destination.open(router); opened += 1 })
            .padding(10)
        try await click(grid, size: NSSize(width: 220, height: 140), at: NSPoint(x: 110, y: 60))
        XCTAssertEqual(opened, 1, "karta tıklayınca Limitler sayfası açılır")
        XCTAssertEqual(router.selectedMainSection, .limits, "kenar çubuğundaki Limitler sayfasına gidilir")
        XCTAssertNotEqual(router.selectedSettingsSection, .agents)
    }
}
