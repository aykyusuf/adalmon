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
        XCTAssertFalse(t.opensDetail)
        XCTAssertEqual(try XCTUnwrap(tile([], connected: true)).value, "Bekleniyor")
        XCTAssertNil(tile([], agents: false), "ajanlar kapalı ve veri yok: gizli")
        let codex = ProviderLimits(source: .codex, fiveHour: LimitWindow(usedPercent: 20, resetsAt: nil), weekly: nil, observedAt: now)
        XCTAssertEqual(try XCTUnwrap(tile([claude(five: 90), codex], agents: false)).value, "Codex %20", "ajanlar kapalıyken yalnız Codex")
    }

    func testStaleShowsAge() throws {
        let t = try XCTUnwrap(tile([claude(five: 50, observed: now.addingTimeInterval(-3 * 3600))]))
        XCTAssertTrue(t.secondary.hasPrefix("Son veri"), t.secondary)
    }

    func testDestinationOpensAgentSettings() {
        XCTAssertEqual(OverviewTileKind.limits.destination, OverviewDestination(section: .overview, settings: .agents))
        let router = SettingsRouter(isDockModeOn: { true })
        OverviewTileKind.limits.destination.open(router)
        XCTAssertEqual(router.selectedSettingsSection, .agents)
    }
}
