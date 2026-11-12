import XCTest
@testable import Adalmon

/// Çok oturumlu limit birleştirme: eski oturumun düşük değeri göstergeyi geri sarmaz.
@MainActor
final class LimitMergeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func claude(five: (Double, TimeInterval)? = nil, weekly: (Double, TimeInterval)? = nil, observed: Date? = nil) -> ProviderLimits {
        ProviderLimits(source: .claude,
                       fiveHour: five.map { LimitWindow(usedPercent: $0.0, resetsAt: now.addingTimeInterval($0.1)) },
                       weekly: weekly.map { LimitWindow(usedPercent: $0.0, resetsAt: now.addingTimeInterval($0.1)) },
                       observedAt: observed ?? now)
    }

    func testLowerValueForSameResetIsIgnoredEntirely() {
        let current = claude(weekly: (11, 86_400))
        XCTAssertNil(LimitMerge.monotonic(current: current, incoming: claude(weekly: (7, 86_400))), "11 sonra 7 (aynı reset): yok sayılır")
        XCTAssertNil(LimitMerge.monotonic(current: current, incoming: claude(weekly: (7, 86_400 + 30))), "±60 sn tolerans içinde aynı pencere")
    }

    func testHigherOrEqualValueForSameResetIsAccepted() throws {
        let current = claude(weekly: (7, 86_400))
        XCTAssertEqual(try XCTUnwrap(LimitMerge.monotonic(current: current, incoming: claude(weekly: (11, 86_400)))).weekly?.usedPercent, 11)
        XCTAssertEqual(try XCTUnwrap(LimitMerge.monotonic(current: current, incoming: claude(weekly: (7, 86_400)))).weekly?.usedPercent, 7)
    }

    func testNewerResetStartsNewWindowAndAcceptsLowerValue() throws {
        let current = claude(weekly: (11, 86_400))
        let merged = try XCTUnwrap(LimitMerge.monotonic(current: current, incoming: claude(weekly: (2, 86_400 + 7 * 86_400))))
        XCTAssertEqual(merged.weekly?.usedPercent, 2)
    }

    func testOlderResetIsIgnored() {
        let current = claude(weekly: (11, 7 * 86_400))
        XCTAssertNil(LimitMerge.monotonic(current: current, incoming: claude(weekly: (30, 86_400))))
    }

    func testWindowsAreMergedIndependently() throws {
        let current = claude(five: (40, 3600), weekly: (11, 86_400))
        // 5 saatlik arttı, haftalık eski oturumdan düşük geldi: 5 saatlik kabul, haftalık mevcut kalır.
        let merged = try XCTUnwrap(LimitMerge.monotonic(current: current, incoming: claude(five: (55, 3600), weekly: (7, 86_400))))
        XCTAssertEqual(merged.fiveHour?.usedPercent, 55)
        XCTAssertEqual(merged.weekly?.usedPercent, 11)
    }

    func testModelKeepsHigherValueAndObservedAtWhenStaleSessionReports() throws {
        let suite = "LimitMergeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SubscriptionLimitsModel(defaults: defaults, usageStore: ModelUsageStore(claudeRoot: URL(filePath: "/nonexistent-a"), codexRoot: URL(filePath: "/nonexistent-b")), live: false)
        model.ingestClaude(claude(weekly: (11, 86_400)), now: now)
        model.ingestClaude(claude(weekly: (7, 86_400)), now: now.addingTimeInterval(15))
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 11)
        XCTAssertEqual(model.claude?.observedAt, now, "yok sayılan değer observedAt'i güncellemez")
        model.ingestClaude(claude(weekly: (12, 86_400)), now: now.addingTimeInterval(30))
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 12)
        model.ingestClaude(claude(weekly: (2, 86_400 + 7 * 86_400)), now: now.addingTimeInterval(45))
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 2, "yeni reset: yeni pencere")
        model.ingestClaude(claude(weekly: (40, 86_400)), now: now.addingTimeInterval(60))
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 2, "eski reset ile gelen yok sayılır")
    }
}
