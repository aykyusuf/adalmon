import XCTest
@testable import Adalmon

final class ChargeLimitLogicTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func config(limit: Int = 80, floor: Int = 75, enabled: Bool = true, topUp: Date? = nil) -> ChargeConfig {
        ChargeConfig(enabled: enabled, limit: limit, sailingFloor: floor, topUpStartedAt: topUp)
    }

    private func decide(_ level: Int?, plugged: Bool = true, inhibited: Bool = false, config: ChargeConfig? = nil,
                        manual: Bool = false, full: Bool = false, at date: Date? = nil) -> ChargeLimitOutcome {
        ChargeLimitLogic.decide(.init(level: level, isPluggedIn: plugged, isFullyCharged: full, config: config ?? self.config(),
                                      manualInhibit: manual, currentlyInhibited: inhibited, now: date ?? now))
    }

    func testChargesBelowLimit() {
        XCTAssertEqual(decide(79).decision, .allow)
        XCTAssertEqual(decide(79).reason, .belowLimit)
    }

    func testInhibitsAtLimit() {
        XCTAssertEqual(decide(80).decision, .inhibit)
        XCTAssertEqual(decide(95).decision, .inhibit)
    }

    func testSailingHoldsUntilBelowFloor() {
        XCTAssertEqual(decide(78, inhibited: true).decision, .inhibit)
        XCTAssertEqual(decide(75, inhibited: true).decision, .inhibit, "alt sınırın ALTINA inmeli")
        XCTAssertEqual(decide(74, inhibited: true).decision, .allow)
        XCTAssertEqual(decide(74, inhibited: true).reason, .resumed)
    }

    func testNoFlappingAcrossDischargeAndRecharge() {
        var inhibited = false
        var transitions = 0
        let levels = Array(70...82) + Array((74...82).reversed()) + Array(70...82)
        for level in levels {
            let d = decide(level, inhibited: inhibited).decision == .inhibit
            if d != inhibited { transitions += 1 }
            inhibited = d
        }
        // 70..82 -> 80'de engel; 82..74 iner (engelli kalır); 73'e inmez; 70'te yeniden başlar sonra 80'de engel
        XCTAssertLessThanOrEqual(transitions, 3)
    }

    func testWatchdogBelowHardFloorAlwaysAllows() {
        XCTAssertEqual(decide(19, inhibited: true).decision, .allow)
        XCTAssertEqual(decide(19, inhibited: true).reason, .belowHardFloor)
        XCTAssertEqual(decide(10, config: config(enabled: false), manual: true).decision, .allow)
        XCTAssertEqual(decide(20, inhibited: true, config: config(limit: 50, floor: 20)).decision, .inhibit, "taban dahil değil: %20 serbest değil")
    }

    func testFailSafeWhenBatteryUnknown() {
        XCTAssertEqual(decide(nil, inhibited: true).decision, .allow)
        XCTAssertEqual(decide(150).decision, .allow)
        XCTAssertEqual(decide(-1).decision, .allow)
    }

    func testUnpluggedAlwaysAllows() {
        XCTAssertEqual(decide(90, plugged: false, inhibited: true).decision, .allow)
    }

    func testDisabledOrNoLimitAllows() {
        XCTAssertEqual(decide(95, config: config(enabled: false)).decision, .allow)
        XCTAssertEqual(decide(95, config: config(limit: 100, floor: 75)).decision, .allow)
    }

    func testInvalidConfigAllows() {
        XCTAssertEqual(decide(95, config: config(limit: 80, floor: 80)).decision, .allow)
        XCTAssertEqual(decide(95, config: config(limit: 83, floor: 75)).decision, .allow)
        XCTAssertEqual(decide(95, config: config(limit: 80, floor: 10)).decision, .allow)
    }

    func testManualInhibitOnlyWhenLimitDisabled() {
        XCTAssertEqual(decide(60, config: config(enabled: false), manual: true).decision, .inhibit)
        XCTAssertEqual(decide(60, config: config(enabled: true), manual: true).decision, .allow)
    }

    // MARK: Şarjı şimdi tamamla

    func testTopUpOverridesLimit() {
        let c = config(topUp: now)
        let out = decide(90, inhibited: true, config: c)
        XCTAssertEqual(out.decision, .allow)
        XCTAssertEqual(out.reason, .topUp)
        XCTAssertFalse(out.endTopUp)
    }

    func testTopUpEndsAtFullUnplugAndTimeout() {
        let c = config(topUp: now)
        XCTAssertTrue(decide(100, config: c).endTopUp)
        XCTAssertTrue(decide(99, config: c, full: true).endTopUp)
        XCTAssertTrue(decide(90, plugged: false, config: c).endTopUp)
        XCTAssertTrue(decide(90, config: c, at: now.addingTimeInterval(HelperConstants.topUpMaxSeconds + 1)).endTopUp)
        XCTAssertTrue(decide(90, config: c, at: now.addingTimeInterval(-3600)).endTopUp, "saat geri alındı")
        // Bitince sınır hemen geri gelir
        XCTAssertEqual(decide(100, config: c).decision, .inhibit)
    }
}
