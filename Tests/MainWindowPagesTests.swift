import XCTest
@testable import Adalmon

@MainActor
final class MainWindowPagesTests: XCTestCase {
    // MARK: Bölümler

    func testSectionOrderAndShortcuts() {
        XCTAssertEqual(MainSection.pages, [.overview, .network, .history, .mobile, .rules, .processes])
        XCTAssertEqual(MainSection.pages.compactMap(\.shortcutKey), ["1", "2", "3", "4", "5", "6"])
        XCTAssertNil(MainSection.settings(.general).shortcutKey)
    }

    func testSectionIDRoundTrip() {
        for section in MainSection.allCases {
            XCTAssertEqual(MainSection(id: section.id), section)
        }
        XCTAssertNil(MainSection(id: "yok"))
    }

    // MARK: Kural taslağı

    func testDraftRoundTripsRollingThrottleRule() throws {
        let rule = UsageRule(name: "Safari", app: "/Applications/Safari.app", scope: .mobileOnly,
                             trigger: .rolling(minutes: 10, bytes: 500_000_000),
                             action: .throttle(downBytesPerSec: 256 * 1024, upBytesPerSec: nil))
        let draft = RuleDraft(rule: rule)
        XCTAssertFalse(draft.isNew)
        XCTAssertEqual(draft.unit, .megabytes)
        XCTAssertEqual(draft.amount, 500)
        XCTAssertEqual(try XCTUnwrap(draft.rule), rule)
    }

    func testDraftFixedWindowAndBlockInGigabytes() throws {
        var draft = RuleDraft()
        draft.app = "/Applications/Chrome.app"
        draft.triggerKind = .fixedWindow
        draft.hours = 3
        draft.amount = 4
        draft.unit = .gigabytes
        draft.actionKind = .block
        draft.scope = .allNetworks
        let rule = try XCTUnwrap(draft.rule)
        XCTAssertEqual(rule.trigger, .fixedWindow(hours: 3, bytes: 4_000_000_000))
        XCTAssertEqual(rule.action, .block)
        XCTAssertEqual(RuleDraft(rule: rule).hours, 3)
        XCTAssertEqual(RuleDraft(rule: rule).unit, .gigabytes)
    }

    func testDraftValidation() {
        var draft = RuleDraft()
        XCTAssertFalse(draft.isValid) // uygulama yok
        draft.app = "x.app"
        XCTAssertTrue(draft.isValid)
        draft.downKB = nil
        draft.upKB = nil
        XCTAssertFalse(draft.isValid) // hız sınırı boş
        draft.actionKind = .block
        XCTAssertTrue(draft.isValid)
        draft.amount = 0
        XCTAssertFalse(draft.isValid)
        draft.amount = 10
        draft.minutes = RuleTrigger.maxRollingMinutes + 1
        XCTAssertFalse(draft.isValid)
    }

    // MARK: Metinler

    func testRuleTextDuration() {
        XCTAssertEqual(RuleText.duration(45), "45 sn")
        XCTAssertEqual(RuleText.duration(12 * 60), "12 dk")
        XCTAssertEqual(RuleText.duration(3_900), "1 sa 5 dk")
        XCTAssertEqual(RuleText.duration(2 * 86_400 + 3 * 3_600), "2 gün 3 sa")
    }

    func testRuleTextTrigger() {
        XCTAssertEqual(RuleText.trigger(.rolling(minutes: 10, bytes: 500_000_000)), "Son 10 dakikada ≥ 500 MB")
        XCTAssertTrue(RuleText.trigger(.fixedWindow(hours: 3, bytes: 4_000_000_000)).hasPrefix("3 saatlik sabit pencerede"))
    }

    // MARK: Geçmiş

    func testHourBarsFill24Slots() {
        let start = Date(timeIntervalSince1970: 1_800_000_000 / 86_400 * 86_400)
        let t0 = Int(start.timeIntervalSince1970)
        let bars = HistoryBuilder.hourBars(points: [UsageStore.HourPoint(hour: t0 + 14 * 3_600, mobileBytes: 5, otherBytes: 7)], dayStart: start)
        XCTAssertEqual(bars.count, 24)
        XCTAssertEqual(bars[14].mobile, 5)
        XCTAssertEqual(bars[14].other, 7)
        XCTAssertEqual(bars[14].target, .hour(t0 + 14 * 3_600))
        XCTAssertEqual(bars[14].label, "14:00 – 15:00")
        XCTAssertEqual(bars[3].axisLabel, "03")
        XCTAssertNil(bars[4].axisLabel)
        XCTAssertEqual(bars.filter { $0.total > 0 }.count, 1)
    }

    func testDayKeysAscendingAndDayBarsFillGaps() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let keys = HistoryBuilder.dayKeys(count: 7, endingAt: end)
        XCTAssertEqual(keys.count, 7)
        XCTAssertEqual(keys, keys.sorted())
        XCTAssertEqual(keys.last, UsageStore.dayKey(end))
        let bars = HistoryBuilder.dayBars(points: [UsageStore.DayPoint(day: keys[2], mobileBytes: 10, otherBytes: 20)], keys: keys)
        XCTAssertEqual(bars.map(\.total), [0, 0, 30, 0, 0, 0, 0])
        XCTAssertTrue(bars.allSatisfy { $0.axisLabel != nil }) // hafta: her çubuk etiketli
        let month = HistoryBuilder.dayBars(points: [], keys: HistoryBuilder.dayKeys(count: 30, endingAt: end))
        XCTAssertEqual(month.last?.axisLabel != nil, true)
        XCTAssertLessThan(month.filter { $0.axisLabel != nil }.count, 10)
    }

    func testLoaderReadsHourlyAndDailySeries() async {
        let dir = FileManager.default.temporaryDirectory.appending(path: "hist-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UsageStore(path: dir.appending(path: "t.sqlite").path)

        let now = Date.now
        let dayStart = Calendar.current.startOfDay(for: now)
        let hour = Int(dayStart.timeIntervalSince1970) + 2 * 3_600
        await store.addInterfaceHourly([(hour: hour, mobile: 100, other: 40)])
        await store.addInterfaceBytes(day: UsageStore.dayKey(now), mobile: true, bytes: 100)
        await store.addInterfaceBytes(day: UsageStore.dayKey(now), mobile: false, bytes: 40)
        await store.add(day: "", rows: [], hourly: [
            UsageStore.HourlyRow(hour: hour, app: "A.app", domain: "x", mobile: true, bytesIn: 60, bytesOut: 40),
        ])

        let day = await HistoryLoader.load(range: .day, offset: 0, store: store, now: now)
        XCTAssertEqual(day.bars[2].mobile, 100)
        XCTAssertEqual(day.bars[2].other, 40)
        XCTAssertEqual(day.defaultSelection, "h2")
        XCTAssertEqual(day.periodTitle, "Bugün")
        let apps = await HistoryDetailLoader(store: store, target: .hour(hour)).topApps()
        XCTAssertEqual(apps, [HistoryAppBytes(app: "A.app", bytes: 100, mobile: 100)])

        let week = await HistoryLoader.load(range: .week, offset: 0, store: store, now: now)
        XCTAssertEqual(week.bars.count, 7)
        XCTAssertEqual(week.bars.last?.mobile, 100)
        XCTAssertEqual(week.totalOther, 40)
        let empty = await HistoryLoader.load(range: .month, offset: 5, store: store, now: now)
        XCTAssertTrue(empty.isEmpty)
    }

    // MARK: Genel bakış

    func testTodaySummaryUsesLargerOfSessionAndStoredDirections() {
        var data = PanelData()
        data.mobileToday = 300
        data.wifiToday = 700
        data.downToday = 100
        data.upToday = 50
        let stats = OverviewDayStats(yesterdayTotal: 2_000, storedDown: 600, storedUp: 20)
        let s = TodaySummary.make(data: data, stats: stats)
        XCTAssertEqual(s.total, 1_000)
        XCTAssertEqual(s.down, 600)
        XCTAssertEqual(s.up, 50)
        XCTAssertEqual(s.versusYesterday, 0.5)
        XCTAssertNil(TodaySummary.make(data: data, stats: OverviewDayStats()).versusYesterday)
    }

    func testAttentionItemsAreConditional() {
        var data = PanelData()
        data.installerState = .active
        let none = OverviewAttention.items(data: data, rules: [], statuses: [], ladder: LadderStatus(), burstThreshold: 50_000_000)
        XCTAssertTrue(none.isEmpty)

        data.installerState = .notInstalled
        data.filterConnected = false
        data.last60 = [AppUsage(app: "/Applications/Safari.app", bytes: 80_000_000, mobileBytes: 0, domains: [])]
        let rule = UsageRule(app: "/Applications/Safari.app", trigger: .rolling(minutes: 5, bytes: 1_000), action: .block)
        var status = RuleStatus(id: rule.id, phase: .active, usedBytes: 2_000, thresholdBytes: 1_000, windowStart: nil, windowEnd: nil,
                                secondsUntilReset: 120, isEnforcedNow: true, pendingFilterSupport: false)
        status.isEnforcedNow = true
        let ladder = LadderStatus(enabled: true, level: .slow, percent: 96)
        let items = OverviewAttention.items(data: data, rules: [rule], statuses: [status], ladder: ladder, burstThreshold: 50_000_000)
        XCTAssertEqual(Set(items.map(\.destination)).count, 3)
        XCTAssertEqual(items.count, 4) // kural, merdiven, filtre, burst
    }

    func testBudgetEtaTextPicksEarliest() {
        let now = Date.now
        var b = BudgetSnapshot(cycleStart: now, nextCycleStart: now, cycleUsedBytes: 0, todayUsedBytes: 0, monthlyCapBytes: nil,
                               remainingBytes: nil, daysLeft: 3, dynamicDailyBudgetBytes: nil, effectiveDailyCapBytes: 1,
                               todayRemainingBytes: 1, etaRecentRate: .notToday, etaAverageRate: .noData)
        XCTAssertEqual(OverviewBudgetSummary.etaText(b), "Bu hızla bugün dolmaz")
        b.etaRecentRate = .noData
        XCTAssertNil(OverviewBudgetSummary.etaText(b))
        b.etaRecentRate = .at(now.addingTimeInterval(3_600))
        XCTAssertEqual(OverviewBudgetSummary.etaText(b)?.hasSuffix("dolar"), true)
        b.etaBudgetRecentRate = .reached
        XCTAssertEqual(OverviewBudgetSummary.etaText(b), "Bugünkü bütçe doldu")
        XCTAssertEqual(OverviewBudgetSummary.daysText(b), "3 gün kaldı")
    }
}
