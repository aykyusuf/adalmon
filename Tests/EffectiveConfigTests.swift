import XCTest
@testable import Adalmon

final class EffectiveConfigTests: XCTestCase {
    private let app = "/Applications/A.app"
    private func limit(_ down: Int?, _ up: Int? = nil, mobile: Bool) -> AppLimit {
        AppLimit(downBytesPerSec: down, upBytesPerSec: up, onlyOnMobile: mobile)
    }
    private func output(_ l: AppLimit, blocked: [String] = []) -> RuleOutput {
        var o = RuleOutput()
        o.limits[app] = [.init(cause: .rule(UUID()), limit: l)]
        for b in blocked { o.blocked[b] = [.rule(UUID())] }
        return o
    }

    func testMostRestrictivePerDirectionWins() {
        let manual = [app: limit(1_000_000, 50_000, mobile: true)]
        let eff = EffectiveConfigBuilder.build(manualLimits: manual, manualBlocked: [], output: output(limit(256_000, 500_000, mobile: true)), onMobile: true)
        XCTAssertEqual(eff.limits[app], limit(256_000, 50_000, mobile: true))
    }

    func testManualEntriesAreNeverRemovedOrReordered() {
        let manual = [app: limit(1_000_000, mobile: false), "/Applications/Other.app": limit(5, mobile: true)]
        let eff = EffectiveConfigBuilder.build(manualLimits: manual, manualBlocked: ["/Applications/Z.app", "/Applications/Y.app"],
                                               output: output(limit(2_000_000, mobile: false), blocked: ["/Applications/Y.app", "/Applications/B.app"]),
                                               onMobile: true)
        XCTAssertEqual(eff.limits["/Applications/Other.app"], manual["/Applications/Other.app"])
        XCTAssertEqual(eff.limits[app], limit(1_000_000, mobile: false)) // elle olan daha sıkı
        XCTAssertEqual(eff.blocked, ["/Applications/Z.app", "/Applications/Y.app", "/Applications/B.app"])
        // Kural çıktısı boşken sonuç elle ayarlarla birebir aynıdır.
        let same = EffectiveConfigBuilder.build(manualLimits: manual, manualBlocked: ["/Applications/Z.app"], output: RuleOutput(), onMobile: false)
        XCTAssertEqual(same.limits, manual)
        XCTAssertEqual(same.blocked, ["/Applications/Z.app"])
    }

    /// Elle: yalnız mobilde 256 KB/s. Kural: tüm ağlarda 2 MB/s. Tek bayrak ikisini birden ifade edemez;
    /// mobildeyken 256 KB/s, Wi-Fi'deyken 2 MB/s (kullanıcının yalnız-mobil sınırı Wi-Fi'ye taşmaz).
    func testMixedScopesResolveAgainstCurrentMedium() {
        let manual = [app: limit(256 * 1024, mobile: true)]
        let rule = output(limit(2 * 1024 * 1024, mobile: false))
        let onMobile = EffectiveConfigBuilder.build(manualLimits: manual, manualBlocked: [], output: rule, onMobile: true)
        XCTAssertEqual(onMobile.limits[app]?.downBytesPerSec, 256 * 1024)
        let onWifi = EffectiveConfigBuilder.build(manualLimits: manual, manualBlocked: [], output: rule, onMobile: false)
        XCTAssertEqual(onWifi.limits[app], limit(2 * 1024 * 1024, mobile: false))
    }

    /// Elle engel kapsamları → filtre yapılandırması (filtre/şema değişmeden):
    /// Mobilde = `blockedOnMobile`; Her yerde = `blockedOnMobile` + her ağda `blockedAlways`;
    /// Wi-Fi'de = yalnız Wi-Fi/kablolu ağdayken `blockedAlways` (mobilde hiç engel yok).
    func testManualBlockScopesMapToExistingFilterConfig() {
        let mobile = "/Applications/M.app", wifi = "/Applications/W.app", all = "/Applications/E.app"
        func build(onMobile: Bool) -> EffectiveConfig {
            EffectiveConfigBuilder.build(manualLimits: [:], manualBlocked: [mobile, all], manualBlockedWiFi: [wifi, all],
                                         output: RuleOutput(), onMobile: onMobile)
        }
        let onWifi = build(onMobile: false)
        XCTAssertEqual(onWifi.blocked, [mobile, all])
        XCTAssertEqual(onWifi.blockedAlways, [wifi, all])
        let onCell = build(onMobile: true)
        XCTAssertEqual(onCell.blocked, [mobile, all])
        XCTAssertEqual(onCell.blockedAlways, [all], "Wi-Fi'de engeli mobilde uygulanmaz")
        // Filtre kararı (FlowPolicy değişmeden): her senaryoda beklenen uygulama engellenir.
        func blocks(_ app: String, _ eff: EffectiveConfig, expensive: Bool) -> Bool {
            let cfg = FilterConfig(blockedOnMobile: eff.blocked, blockedAlways: eff.blockedAlways)
            return FlowPolicy.shouldBlock(app: app, kind: .direct, expensive: expensive, config: cfg)
        }
        XCTAssertEqual([mobile, wifi, all].map { blocks($0, onWifi, expensive: false) }, [false, true, true])
        XCTAssertEqual([mobile, wifi, all].map { blocks($0, onCell, expensive: true) }, [true, false, true])
    }

    /// Her ağda engellenen uygulamanın hız sınırı gönderilmez (saydam proxy akışı üstlenip engeli atlatmasın).
    func testAlwaysBlockedAppHasNoLimitInConfig() {
        let manual = [app: limit(100_000, mobile: false)]
        let wifiBlocked = EffectiveConfigBuilder.build(manualLimits: manual, manualBlocked: [], manualBlockedWiFi: [app],
                                                       output: RuleOutput(), onMobile: false)
        XCTAssertNil(wifiBlocked.limits[app])
        let onCell = EffectiveConfigBuilder.build(manualLimits: manual, manualBlocked: [], manualBlockedWiFi: [app],
                                                  output: RuleOutput(), onMobile: true)
        XCTAssertEqual(onCell.limits[app], manual[app], "mobilde Wi-Fi'de engeli yok, sınır geçerli")
    }

    func testMobileOnlyRuleDoesNotLeakToWifiOverWideManualLimit() {
        let manual = [app: limit(1_000_000, mobile: false)]
        let rule = output(limit(100_000, mobile: true))
        XCTAssertEqual(EffectiveConfigBuilder.build(manualLimits: manual, manualBlocked: [], output: rule, onMobile: false).limits[app]?.downBytesPerSec, 1_000_000)
        XCTAssertEqual(EffectiveConfigBuilder.build(manualLimits: manual, manualBlocked: [], output: rule, onMobile: true).limits[app]?.downBytesPerSec, 100_000)
    }

    func testIsStricter() {
        XCTAssertTrue(EffectiveConfigBuilder.isStricter(limit(100, mobile: true), than: nil))
        XCTAssertTrue(EffectiveConfigBuilder.isStricter(limit(100, mobile: true), than: limit(200, mobile: true)))
        XCTAssertFalse(EffectiveConfigBuilder.isStricter(limit(300, mobile: true), than: limit(200, mobile: true)))
        XCTAssertTrue(EffectiveConfigBuilder.isStricter(limit(200, mobile: false), than: limit(200, mobile: true)))
    }

    func testTierLadderThresholdsAreInclusiveAndNormalized() {
        var c = TierLadderConfig()
        XCTAssertEqual(TierLadder.level(percent: 79.99, config: c), .none)
        XCTAssertEqual(TierLadder.level(percent: 80, config: c), .warn)
        XCTAssertEqual(TierLadder.level(percent: 95, config: c), .slow)
        XCTAssertEqual(TierLadder.level(percent: 100, config: c), .cut)
        c.warnPercent = 90; c.slowPercent = 50; c.cutPercent = 10 // bozuk sıra düzeltilir
        XCTAssertEqual(c.normalized.cutPercent, 90)
        XCTAssertEqual(TierLadder.percent(dailyUsed: 500, dailyCap: 1000, cycleUsed: 9000, monthlyCap: 10_000), 90)
        XCTAssertEqual(TierLadder.percent(dailyUsed: 500, dailyCap: 0), 0)
    }

    func testModelsRoundTripAndTolerateMissingFields() throws {
        let rule = UsageRule(name: "n", app: app, scope: .allNetworks, trigger: .fixedWindow(hours: 3, bytes: 4_000_000_000),
                             action: .throttle(downBytesPerSec: 1, upBytesPerSec: nil))
        let data = try JSONEncoder().encode([rule])
        XCTAssertEqual(try JSONDecoder().decode([UsageRule].self, from: data), [rule])
        let old = try JSONDecoder().decode(TierLadderConfig.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertTrue(old.enabled)
        XCTAssertEqual(old.warnPercent, 80)
        XCTAssertEqual(old.slowDownBytesPerSec, 256 * 1024)
        XCTAssertEqual(try JSONDecoder().decode(DataSaverConfig.self, from: Data("{}".utf8)), DataSaverConfig())
        XCTAssertEqual(rule.trigger.windowMinutes, 180)
        XCTAssertEqual(RuleTrigger.rolling(minutes: 99_999, bytes: 1).windowMinutes, RuleTrigger.maxRollingMinutes)
        // Boş hız sınırı etkisiz.
        XCTAssertFalse(UsageRule(app: app, trigger: .rolling(minutes: 10, bytes: 1), action: .throttle(downBytesPerSec: nil, upBytesPerSec: 0)).hasEffect)
    }

    func testFilterConfigStillDecodesOldJSON() throws {
        let cfg = try JSONDecoder().decode(FilterConfig.self, from: Data(#"{"proxyPorts":[8080]}"#.utf8))
        XCTAssertEqual(cfg.proxyPorts, [8080])
        XCTAssertTrue(cfg.limits.isEmpty)
    }
}
