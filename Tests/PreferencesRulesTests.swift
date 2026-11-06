import XCTest
@testable import Adalmon

@MainActor
final class PreferencesRulesTests: XCTestCase {
    private func withSuite(_ body: (UserDefaults) -> Void) {
        let name = "adalmon-prefs-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        body(d)
    }

    func testBillingDayIsClampedAndPersisted() {
        withSuite { d in
            let p = Preferences(defaults: d)
            XCTAssertEqual(p.billingCycleStartDay, 1)
            p.billingCycleStartDay = 31
            XCTAssertEqual(p.billingCycleStartDay, 28)
            XCTAssertEqual(Preferences(defaults: d).billingCycleStartDay, 28)
            p.billingCycleStartDay = 0
            XCTAssertEqual(Preferences(defaults: d).billingCycleStartDay, 1)
        }
    }

    func testMonthlyCapOptionalAndRulesLadderDataSaverSurvive() {
        withSuite { d in
            let p = Preferences(defaults: d)
            XCTAssertNil(p.monthlyCapGB)
            XCTAssertNil(p.monthlyCapBytes)
            p.monthlyCapGB = 30
            XCTAssertEqual(Preferences(defaults: d).monthlyCapBytes, 30_000_000_000)
            p.monthlyCapGB = nil
            XCTAssertNil(Preferences(defaults: d).monthlyCapGB)
            XCTAssertNil(d.object(forKey: "monthlyCapGB"))

            let rule = UsageRule(name: "YouTube 10 dk", app: "/Applications/Google Chrome.app", scope: .allNetworks,
                                 trigger: .rolling(minutes: 10, bytes: 100_000_000), action: .throttle(downBytesPerSec: 262_144, upBytesPerSec: nil))
            p.usageRules = [rule]
            var tier = TierLadderConfig()
            tier.enabled = true
            tier.slowPercent = 90
            p.tierLadder = tier
            p.dataSaver = { var s = DataSaverConfig(); s.enabled = true; s.allowlist = ["/Applications/Mail.app"]; return s }()
            let q = Preferences(defaults: d)
            XCTAssertEqual(q.usageRules, [rule])
            XCTAssertEqual(q.tierLadder, tier)
            XCTAssertEqual(q.dataSaver.allowlist, ["/Applications/Mail.app"])
            XCTAssertTrue(q.dataSaver.enabled)
        }
    }
}
