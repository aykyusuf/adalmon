import XCTest
@testable import Adalmon

@MainActor
final class RuleEngineTests: XCTestCase {
    private let chrome = "/Applications/Google Chrome.app"
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let ctx = RuleEngine.Context(ownAppKey: "/Applications/Adalmon.app", proxyOwnerPaths: ["/Users/u/Desktop/spoofdpi"])
    private let noLadder = RuleEngine.LadderInput(dayKey: "2027-01-15", dailyUsed: 0, dailyCap: 3_000_000_000, cycleUsed: nil, monthlyCap: nil)
    private let MB: UInt64 = 1_000_000

    private func bucket(_ app: String? = nil, bytes: UInt64, expensive: Bool = true, at t: Date, kind: FlowKind = .direct) -> UsageBucket {
        UsageBucket(app: app ?? chrome, signingID: "", host: "x.com", kind: kind, expensive: expensive,
                    minute: Int(t.timeIntervalSince1970 / 60), bytesIn: bytes, bytesOut: 0)
    }

    private func rolling(minutes: Int = 10, mb: UInt64 = 100, scope: NetworkScope = .mobileOnly,
                         action: RuleAction = .throttle(downBytesPerSec: 256 * 1024, upBytesPerSec: nil)) -> UsageRule {
        UsageRule(name: "r", app: chrome, scope: scope, trigger: .rolling(minutes: minutes, bytes: mb * MB), action: action)
    }

    private func fixed(hours: Int = 3, gb: UInt64 = 4, scope: NetworkScope = .mobileOnly, action: RuleAction = .block) -> UsageRule {
        UsageRule(name: "q", app: chrome, scope: scope, trigger: .fixedWindow(hours: hours, bytes: gb * 1000 * MB), action: action)
    }

    private func engine(_ rules: [UsageRule], url: URL? = nil) -> RuleEngine {
        let e = RuleEngine(stateURL: url)
        e.setRules(rules)
        return e
    }

    private func tick(_ e: RuleEngine, _ now: Date, bytes: UInt64 = 0, expensive: Bool = true) -> [RuleEngine.Event] {
        if bytes > 0 { e.ingest([bucket(bytes: bytes, expensive: expensive, at: now)], now: now) } else { e.ingest([], now: now) }
        return e.evaluate(now: now, tier: TierLadderConfig(), ladderInput: noLadder, context: ctx)
    }

    // MARK: Halka tamponu

    func testRingSumsLastNMinutesAndExpires() {
        var r = MinuteRing(capacity: 60)
        for m in 100..<110 { r.add(minute: m, total: 10, mobile: 4) }
        XCTAssertEqual(r.sum(lastMinutes: 10, endingAt: 109, mobileOnly: false), 100)
        XCTAssertEqual(r.sum(lastMinutes: 3, endingAt: 109, mobileOnly: false), 30)
        XCTAssertEqual(r.sum(lastMinutes: 10, endingAt: 109, mobileOnly: true), 40)
        // 10 dk sonra hepsi pencere dışında.
        XCTAssertEqual(r.sum(lastMinutes: 10, endingAt: 119, mobileOnly: false), 0)
        // Aynı yuvayı yeniden kullanan yeni dakika eskiyi siler (kapasite 60).
        r.add(minute: 160, total: 7, mobile: 7)
        XCTAssertEqual(r.sum(lastMinutes: 1, endingAt: 160, mobileOnly: false), 7)
        XCTAssertEqual(r.sum(lastMinutes: 60, endingAt: 160, mobileOnly: false), 97) // 101...109 hâlâ pencerede
        // Çok eski (yuvası devredilmiş) kova yok sayılır.
        r.add(minute: 100, total: 999, mobile: 999)
        XCTAssertEqual(r.sum(lastMinutes: 60, endingAt: 160, mobileOnly: false), 97)
    }

    // MARK: Sabit pencere

    func testFixedWindowStartsAtFirstUsageTriggersAndLiftsAtWindowEnd() {
        let rule = fixed()
        let e = engine([rule])
        XCTAssertTrue(tick(e, t0).isEmpty)
        // İlk kullanım pencereyi başlatır.
        let first = t0.addingTimeInterval(600)
        XCTAssertTrue(tick(e, first, bytes: 3000 * MB).isEmpty)
        var st = e.statuses(now: first, onMobile: true)[0]
        XCTAssertEqual(st.windowStart, first)
        XCTAssertEqual(st.usedBytes, 3000 * MB)
        XCTAssertEqual(st.phase, .idle)
        // Eşik aşılınca tetiklenir; engel mobil için çıktıya girer.
        let hit = first.addingTimeInterval(3600)
        XCTAssertEqual(tick(e, hit, bytes: 1000 * MB), [.ruleFired(id: rule.id, app: chrome)])
        XCTAssertEqual(e.output.blocked[chrome], [.rule(rule.id)])
        // Pencere bitmeden kalkmaz (kullanım yoksa bile).
        XCTAssertTrue(tick(e, first.addingTimeInterval(3 * 3600 - 1)).isEmpty)
        XCTAssertNotNil(e.output.blocked[chrome])
        st = e.statuses(now: first.addingTimeInterval(3 * 3600 - 1), onMobile: true)[0]
        XCTAssertEqual(st.secondsUntilReset ?? -1, 1, accuracy: 0.001)
        // Pencere bittiği anda sayaç sıfırlanır ve eylem kalkar.
        let end = first.addingTimeInterval(3 * 3600)
        XCTAssertEqual(tick(e, end), [.ruleLifted(id: rule.id, app: chrome)])
        XCTAssertNil(e.output.blocked[chrome])
        st = e.statuses(now: end, onMobile: true)[0]
        XCTAssertEqual(st.usedBytes, 0)
        XCTAssertNil(st.windowStart)
        // Yeni pencere bir sonraki kullanımda başlar.
        let next = end.addingTimeInterval(1000)
        _ = tick(e, next, bytes: 10 * MB)
        XCTAssertEqual(e.statuses(now: next, onMobile: true)[0].windowStart, next)
    }

    func testMobileOnlyRuleIgnoresWifiBytesButAllNetworksCountsThem() {
        let mobileRule = fixed(gb: 1, scope: .mobileOnly)
        let allRule = fixed(gb: 1, scope: .allNetworks)
        let e = engine([mobileRule, allRule])
        _ = tick(e, t0, bytes: 2000 * MB, expensive: false)
        let st = e.statuses(now: t0, onMobile: false)
        XCTAssertEqual(st[0].usedBytes, 0)
        XCTAssertNil(st[0].windowStart)
        XCTAssertEqual(st[1].usedBytes, 2000 * MB)
        XCTAssertEqual(st[1].phase, .active)
        // Tüm ağlar kapsamlı ENGEL (Faz B): Wi-Fi'de de uygulanır (`blockedAlways`), bekleyen destek yok.
        XCTAssertFalse(st[1].pendingFilterSupport)
        XCTAssertTrue(st[1].isEnforcedNow) // Wi-Fi'de de
        XCTAssertTrue(e.statuses(now: t0, onMobile: true)[1].isEnforcedNow)
        XCTAssertTrue(e.output.pendingFilterSupport.isEmpty)
        XCTAssertEqual(e.output.blockedAlways, [chrome])
        XCTAssertEqual(e.output.blocked[chrome], [.rule(allRule.id)])
    }

    func testProxyEgressIsNotCounted() {
        let e = engine([fixed(gb: 1)])
        e.ingest([bucket(bytes: 5000 * MB, at: t0, kind: .proxyEgress)], now: t0)
        XCTAssertEqual(e.statuses(now: t0, onMobile: true)[0].usedBytes, 0)
    }

    func testFixedWindowStateSurvivesRestartAndExpiresWhileClosed() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rule-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let rule = fixed(gb: 1)
        let e = engine([rule], url: url)
        _ = tick(e, t0, bytes: 1500 * MB)
        XCTAssertNotNil(e.output.blocked[chrome])
        e.persistIfNeeded(now: t0, force: true, synchronous: true)

        // 1 saat sonra yeniden başlatma: pencere sürüyor, eylem hâlâ uygulanır, sayaç korunur.
        let later = t0.addingTimeInterval(3600)
        let e2 = engine([rule], url: url)
        _ = e2.evaluate(now: later, tier: TierLadderConfig(), ladderInput: noLadder, context: ctx)
        XCTAssertEqual(e2.statuses(now: later, onMobile: true)[0].usedBytes, 1500 * MB)
        XCTAssertNotNil(e2.output.blocked[chrome])

        // Uygulama kapalıyken pencere dolmuş: açılışta sıfırlanır ve kalkar.
        let e3 = engine([rule], url: url)
        let events = e3.evaluate(now: t0.addingTimeInterval(4 * 3600), tier: TierLadderConfig(), ladderInput: noLadder, context: ctx)
        XCTAssertEqual(events, [.ruleLifted(id: rule.id, app: chrome)])
        XCTAssertNil(e3.output.blocked[chrome])
    }

    // MARK: Kayan pencere, histerezis

    func testRollingTriggersAtThresholdAndAppliesThrottle() {
        let rule = rolling()
        let e = engine([rule])
        XCTAssertTrue(tick(e, t0, bytes: 99 * MB).isEmpty)
        XCTAssertNil(e.output.limits[chrome])
        XCTAssertEqual(tick(e, t0.addingTimeInterval(1), bytes: 1 * MB), [.ruleFired(id: rule.id, app: chrome)])
        let l = e.output.limits[chrome]?.first
        XCTAssertEqual(l?.cause, .rule(rule.id))
        XCTAssertEqual(l?.limit, AppLimit(downBytesPerSec: 256 * 1024, upBytesPerSec: nil, onlyOnMobile: true))
    }

    /// Kısıtlamaya rağmen uygulama hız sınırı hızında indirmeye devam ediyor: eylem tutma süresi boyunca bir kez
    /// uygulanır, titremez (yalnızca bir apply, kalkma yok çünkü kullanım eşiğin %80'inin altına inmedi).
    func testNoFlapWhileSteadyUsageStaysAboveReleaseLevel() {
        let rule = rolling(minutes: 10, mb: 100)
        let e = engine([rule])
        var fired = 0, lifted = 0
        _ = tick(e, t0, bytes: 100 * MB)
        fired += 1
        // 30 dakika boyunca dakikada 15 MB (256 KB/s ~ 15 MB/dk): 10 dk ≈ 150 MB > 80 MB.
        var now = t0
        for _ in 0..<(30 * 6) {
            now = now.addingTimeInterval(10)
            for ev in tick(e, now, bytes: 2_500_000) {
                if case .ruleFired = ev { fired += 1 }
                if case .ruleLifted = ev { lifted += 1 }
            }
        }
        XCTAssertEqual(fired, 1)
        XCTAssertEqual(lifted, 0)
        XCTAssertNotNil(e.output.limits[chrome])
    }

    func testHoldCooldownAndHysteresisBandOnBlockAction() {
        let rule = rolling(minutes: 10, mb: 100, action: .block)
        let e = engine([rule])
        var events: [RuleEngine.Event] = []
        events += tick(e, t0, bytes: 100 * MB)
        XCTAssertEqual(events, [.ruleFired(id: rule.id, app: chrome)])
        // Kullanım durdu; en az tutma süresi (10 dk) dolmadan kalkmaz. Pencere ilk 9 dk'da hâlâ 100 MB gösterir.
        events = []
        for s in stride(from: 30, through: 9 * 60 + 50, by: 10) { events += tick(e, t0.addingTimeInterval(Double(s))) }
        XCTAssertTrue(events.isEmpty)
        XCTAssertNotNil(e.output.blocked[chrome])
        // 11 dk: pencere boşaldı + tutma süresi geçti → kalkar.
        events = tick(e, t0.addingTimeInterval(11 * 60 + 1))
        XCTAssertEqual(events, [.ruleLifted(id: rule.id, app: chrome)])
        XCTAssertNil(e.output.blocked[chrome])
        // Bekleme (cooldown) bitmeden yeniden tetiklenmez, eşik aşılsa bile.
        let t1 = t0.addingTimeInterval(11 * 60 + 5)
        XCTAssertTrue(tick(e, t1, bytes: 200 * MB).isEmpty)
        XCTAssertEqual(e.statuses(now: t1, onMobile: true)[0].phase, .cooldown)
        // Bekleme bitince, kullanım hâlâ eşiğin üstündeyse yeniden tetiklenir.
        let t2 = t0.addingTimeInterval(11 * 60 + 70)
        XCTAssertEqual(tick(e, t2), [.ruleFired(id: rule.id, app: chrome)])
    }

    func testHysteresisBandKeepsActionUntilBelowEightyPercent() {
        // Eşik 100 MB; eylem 10 dk tutulur. Tutma süresi geçtikten sonra pencerede 90 MB var (≥ %80) → kalkmaz.
        let rule = rolling(minutes: 10, mb: 100, action: .block)
        let e = engine([rule])
        _ = tick(e, t0, bytes: 100 * MB)
        _ = tick(e, t0.addingTimeInterval(9 * 60 + 30), bytes: 90 * MB) // pencerede kalacak
        let now = t0.addingTimeInterval(10 * 60 + 40) // ilk 100 MB düştü, 90 MB kaldı
        XCTAssertTrue(tick(e, now).isEmpty)
        XCTAssertNotNil(e.output.blocked[chrome])
        // Pencere boşalınca kalkar.
        let later = t0.addingTimeInterval(21 * 60)
        XCTAssertEqual(tick(e, later), [.ruleLifted(id: rule.id, app: chrome)])
    }

    func testEssentialAppsAreNeverBlockedByRules() {
        var r = fixed(gb: 1)
        r.app = "/Users/u/Desktop/spoofdpi"
        let e = engine([r])
        e.ingest([bucket("/Users/u/Desktop/spoofdpi", bytes: 2000 * MB, at: t0)], now: t0)
        _ = e.evaluate(now: t0, tier: TierLadderConfig(), ladderInput: noLadder, context: ctx)
        XCTAssertNil(e.output.blocked["/Users/u/Desktop/spoofdpi"])
        var own = fixed(gb: 1)
        own.app = "/Applications/Adalmon.app"
        let e2 = engine([own])
        e2.ingest([bucket("/Applications/Adalmon.app", bytes: 2000 * MB, at: t0)], now: t0)
        _ = e2.evaluate(now: t0, tier: TierLadderConfig(), ladderInput: noLadder, context: ctx)
        XCTAssertTrue(e2.output.isEmpty)
    }

    func testDisabledOrRemovedRuleLiftsAction() {
        var rule = fixed(gb: 1)
        let e = engine([rule])
        _ = tick(e, t0, bytes: 2000 * MB)
        XCTAssertNotNil(e.output.blocked[chrome])
        rule.enabled = false
        e.setRules([rule])
        _ = tick(e, t0.addingTimeInterval(1))
        XCTAssertTrue(e.output.isEmpty)
        XCTAssertEqual(e.statuses(now: t0, onMobile: true)[0].phase, .disabled)
    }

    // MARK: Kademeli limit

    private func ladderInput(used: UInt64, cap: UInt64 = 1000, day: String = "2027-01-15") -> RuleEngine.LadderInput {
        RuleEngine.LadderInput(dayKey: day, dailyUsed: used, dailyCap: cap, cycleUsed: nil, monthlyCap: nil)
    }

    func testLadderTiersThrottleThenBlockTopNonSystemApps() {
        let e = engine([])
        var tier = TierLadderConfig()
        tier.enabled = true
        tier.cutTopCount = 2
        let apps = ["/Applications/A.app": 500 * MB, "/Applications/B.app": 300 * MB, "/Applications/C.app": 100 * MB,
                    "/usr/libexec/nsurlsessiond": 900 * MB, "/Applications/Adalmon.app": 50 * MB, "/Users/u/Desktop/spoofdpi": 50 * MB]
        e.ingest(apps.map { bucket($0.key, bytes: $0.value, at: t0) }, now: t0)

        var events = e.evaluate(now: t0, tier: tier, ladderInput: ladderInput(used: 790), context: ctx)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(e.ladderStatus.level, .none)

        events = e.evaluate(now: t0, tier: tier, ladderInput: ladderInput(used: 800), context: ctx)
        XCTAssertEqual(events, [.ladderReached(.warn)])
        XCTAssertTrue(e.output.isEmpty)

        events = e.evaluate(now: t0, tier: tier, ladderInput: ladderInput(used: 950), context: ctx)
        XCTAssertEqual(events, [.ladderReached(.slow)])
        // Yalnızca korunmayanlar yavaşlatılır; sistem yolu, Adalmon ve proxy sahibi muaf.
        XCTAssertEqual(Set(e.output.limits.keys), ["/Applications/A.app", "/Applications/B.app", "/Applications/C.app"])
        XCTAssertEqual(e.output.limits["/Applications/A.app"]?.first?.limit,
                       AppLimit(downBytesPerSec: 256 * 1024, upBytesPerSec: nil, onlyOnMobile: true))
        XCTAssertTrue(e.output.blocked.isEmpty)

        events = e.evaluate(now: t0, tier: tier, ladderInput: ladderInput(used: 1000), context: ctx)
        XCTAssertEqual(events, [.ladderReached(.cut)])
        XCTAssertEqual(Set(e.output.blocked.keys), ["/Applications/A.app", "/Applications/B.app"]) // en çok tüketen 2
        XCTAssertEqual(e.ladderStatus.blockedApps.count, 2)
        // Her kademe gün başına bir kez bildirilir.
        XCTAssertTrue(e.evaluate(now: t0, tier: tier, ladderInput: ladderInput(used: 1200), context: ctx).isEmpty)
        // Gün sınırında sıfırlanır.
        events = e.evaluate(now: t0.addingTimeInterval(86400), tier: tier, ladderInput: ladderInput(used: 10, day: "2027-01-16"), context: ctx)
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(e.output.isEmpty)
        XCTAssertEqual(e.ladderStatus.level, .none)
    }

    func testLadderUserProtectedListAndAllNetworksPendingFilterSupport() {
        let e = engine([])
        var tier = TierLadderConfig()
        tier.enabled = true
        tier.appliesTo = .allNetworks
        tier.protectedApps = ["/Applications/Zoom.app"]
        e.ingest([bucket("/Applications/Zoom.app", bytes: 900 * MB, at: t0), bucket("/Applications/A.app", bytes: 10 * MB, at: t0)], now: t0)
        _ = e.evaluate(now: t0, tier: tier, ladderInput: ladderInput(used: 1000), context: ctx)
        XCTAssertNil(e.output.limits["/Applications/Zoom.app"])
        XCTAssertNil(e.output.blocked["/Applications/Zoom.app"])
        XCTAssertEqual(e.output.limits["/Applications/A.app"]?.first?.limit.onlyOnMobile, false)
        XCTAssertFalse(e.output.ladderPendingFilterSupport)
        XCTAssertFalse(e.ladderStatus.pendingFilterSupport)
        XCTAssertEqual(e.output.blockedAlways, ["/Applications/A.app"]) // tüm ağlar: Wi-Fi'de de kesilir
    }

    /// Aylık limitin tuttuğu kesme kademesi gün sınırında bozulmaz (engeller kalkıp yeniden kurulmaz).
    func testMonthlyDrivenCutSurvivesDayChange() {
        let e = engine([])
        var tier = TierLadderConfig()
        tier.enabled = true
        e.ingest([bucket("/Applications/A.app", bytes: 10 * MB, at: t0)], now: t0)
        func input(day: String, today: UInt64) -> RuleEngine.LadderInput {
            RuleEngine.LadderInput(dayKey: day, dailyUsed: today, dailyCap: 1000, cycleUsed: 1000 + today, monthlyCap: 1000)
        }
        _ = e.evaluate(now: t0, tier: tier, ladderInput: input(day: "d1", today: 5), context: ctx)
        XCTAssertEqual(e.ladderStatus.level, .cut)
        let before = e.output
        XCTAssertNotNil(before.blocked["/Applications/A.app"])
        _ = e.evaluate(now: t0.addingTimeInterval(86400), tier: tier, ladderInput: input(day: "d2", today: 0), context: ctx)
        XCTAssertEqual(e.ladderStatus.level, .cut)
        XCTAssertEqual(e.output, before)
        // Dönem sıfırlanınca (aylık kullanım 0) her şey kalkar.
        let reset = RuleEngine.LadderInput(dayKey: "d3", dailyUsed: 0, dailyCap: 1000, cycleUsed: 0, monthlyCap: 1000)
        _ = e.evaluate(now: t0.addingTimeInterval(2 * 86400), tier: tier, ladderInput: reset, context: ctx)
        XCTAssertTrue(e.output.isEmpty)
    }

    func testLadderMonthlyCapDrivesLevelAndDisabledLadderProducesNothing() {
        let e = engine([])
        var tier = TierLadderConfig()
        e.ingest([bucket("/Applications/A.app", bytes: 10 * MB, at: t0)], now: t0)
        let monthly = RuleEngine.LadderInput(dayKey: "d", dailyUsed: 10, dailyCap: 1000, cycleUsed: 960, monthlyCap: 1000)
        _ = e.evaluate(now: t0, tier: tier, ladderInput: monthly, context: ctx) // kapalı
        XCTAssertTrue(e.output.isEmpty)
        tier.enabled = true
        _ = e.evaluate(now: t0, tier: tier, ladderInput: monthly, context: ctx)
        XCTAssertEqual(e.ladderStatus.level, .slow)
        XCTAssertEqual(e.ladderStatus.percent, 96)
    }
}
