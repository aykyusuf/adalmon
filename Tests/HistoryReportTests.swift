import XCTest
@testable import Adalmon

final class HistoryReportTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "history-report-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func makeStore() -> UsageStore { UsageStore(path: dir.appending(path: "t.sqlite").path) }

    private func use(_ app: String, _ host: String, mobile: Bool, _ bytes: UInt64) -> UsageStore.Row {
        UsageStore.Row(app: app, host: host, mobile: mobile, bytesIn: bytes, bytesOut: 1)
    }

    // MARK: Store

    func testTopAppsAndDomainsAcrossDayRangeUseDailyTable() async {
        let s = makeStore()
        await s.add(day: "2027-01-10", rows: [
            use("A", "rr1.googlevideo.com", mobile: true, 100), use("A", "i.ytimg.com", mobile: true, 50),
            use("B", "cdn.example.org", mobile: false, 400),
        ])
        await s.add(day: "2027-01-11", rows: [use("A", "rr2.googlevideo.com", mobile: false, 300), use("C", "cdn.example.org", mobile: false, 10)])
        await s.add(day: "2027-01-20", rows: [use("Z", "late.example.net", mobile: false, 9_999)]) // aralık dışı

        let apps = await s.topApps(fromDay: "2027-01-10", toDay: "2027-01-11", limit: 2)
        XCTAssertEqual(apps.map(\.app), ["A", "B"]) // A: 100+1+50+1+300+1 = 453, B: 401, C: 11
        XCTAssertEqual(apps[0], UsageStore.AppHourBytes(app: "A", bytes: 453, mobileBytes: 152))
        XCTAssertEqual(apps[1], UsageStore.AppHourBytes(app: "B", bytes: 401, mobileBytes: 0))
        let one = await s.topApps(fromDay: "2027-01-11", toDay: "2027-01-11")
        XCTAssertEqual(one.map(\.app), ["A", "C"])

        let domains = await s.topDomains(fromDay: "2027-01-10", toDay: "2027-01-11", limit: 5)
        XCTAssertEqual(domains.first, UsageStore.DomainBytes(name: "YouTube", bytes: 453))
        XCTAssertTrue(domains.contains(UsageStore.DomainBytes(name: "example.org", bytes: 412)))
        XCTAssertEqual(domains.count, 2)
        let limited = await s.topDomains(fromDay: "2027-01-10", toDay: "2027-01-11", limit: 1)
        XCTAssertEqual(limited.map(\.name), ["YouTube"])

        let attributed = await s.attributedBytes(fromDay: "2027-01-10", toDay: "2027-01-11")
        XCTAssertEqual(attributed, 453 + 401 + 11)
        let none = await s.attributedBytes(fromDay: "2027-02-01", toDay: "2027-02-05")
        XCTAssertEqual(none, 0)
        let inverted = await s.topApps(fromDay: "2027-01-11", toDay: "2027-01-10")
        XCTAssertTrue(inverted.isEmpty)
    }

    func testReportLoaderCombinesTotalsPreviousPeriodAndApps() async {
        let s = makeStore()
        let period = HistoryReportPeriod(fromDay: "2027-01-10", toDay: "2027-01-11", title: "t", subtitle: "s", dayCount: 2,
                                         includesToday: false, previousFromDay: "2027-01-08", previousToDay: "2027-01-09")
        await s.addInterfaceBytes(day: "2027-01-10", mobile: true, bytes: 500)
        await s.addInterfaceBytes(day: "2027-01-10", mobile: false, bytes: 1_500)
        await s.addInterfaceBytes(day: "2027-01-11", mobile: false, bytes: 1_000)
        await s.addInterfaceBytes(day: "2027-01-09", mobile: false, bytes: 2_000)
        await s.add(day: "2027-01-10", rows: [use("A", "x.example.com", mobile: true, 700)])
        let report = await HistoryReportLoader.load(period: period, store: s)
        XCTAssertEqual(report.mobile, 500)
        XCTAssertEqual(report.other, 2_500)
        XCTAssertEqual(report.total, 3_000)
        XCTAssertEqual(report.previousTotal, 2_000)
        XCTAssertEqual(report.changeText, "+%50")
        XCTAssertEqual(report.dailyAverage, 1_500)
        XCTAssertEqual(report.apps.map(\.app), ["A"])
        XCTAssertEqual(report.attributed, 701)
        XCTAssertEqual(try XCTUnwrap(report.attributedFraction), 701.0 / 3_000.0, accuracy: 0.0001)
    }

    func testReportWithoutDataIsEmptyAndHasNoComparison() async {
        let s = makeStore()
        let period = HistoryReportPeriod.make(range: .week, offset: 40)
        let report = await HistoryReportLoader.load(period: period, store: s)
        XCTAssertTrue(report.isEmpty)
        XCTAssertNil(report.changeText)
        XCTAssertNil(report.dailyAverage)
    }

    // MARK: Dönem

    private func date(_ iso: String) -> Date { HistoryBuilder.date(fromDayKey: iso)!.addingTimeInterval(12 * 3_600) }

    func testPeriodsForPresets() {
        let now = date("2027-03-15")
        let yesterday = HistoryReportPeriod.make(range: .day, offset: 1, now: now)
        XCTAssertEqual(yesterday.fromDay, "2027-03-14")
        XCTAssertEqual(yesterday.toDay, "2027-03-14")
        XCTAssertEqual(yesterday.title, "Dün")
        XCTAssertEqual(yesterday.previousFromDay, "2027-03-13")
        XCTAssertEqual(yesterday.dayCount, 1)
        XCTAssertFalse(yesterday.includesToday)
        XCTAssertTrue(yesterday.isComparable)

        let today = HistoryReportPeriod.make(range: .day, offset: 0, now: now)
        XCTAssertEqual(today.title, "Bugün")
        XCTAssertTrue(today.includesToday)
        XCTAssertFalse(today.isComparable)

        let week = HistoryReportPeriod.make(range: .week, offset: 0, now: now)
        XCTAssertEqual(week.title, "Son 7 gün")
        XCTAssertEqual(week.fromDay, "2027-03-09")
        XCTAssertEqual(week.toDay, "2027-03-15")
        XCTAssertEqual(week.previousFromDay, "2027-03-02")
        XCTAssertEqual(week.previousToDay, "2027-03-08")
        XCTAssertTrue(week.isComparable)

        let month = HistoryReportPeriod.make(range: .month, offset: 0, calendarMonth: true, now: now)
        XCTAssertEqual(month.title, "Bu ay")
        XCTAssertEqual(month.fromDay, "2027-03-01")
        XCTAssertEqual(month.toDay, "2027-03-15")
        XCTAssertEqual(month.dayCount, 15)
        XCTAssertEqual(month.previousToDay, "2027-02-28")
        XCTAssertEqual(month.previousFromDay, "2027-02-14")

        // Takvim ayı bayrağı yalnız Ay + sayfa 0 iken geçerli.
        let older = HistoryReportPeriod.make(range: .month, offset: 1, calendarMonth: true, now: now)
        XCTAssertNotEqual(older.title, "Bu ay")
        XCTAssertEqual(older.dayCount, 30)
        let rolling = HistoryReportPeriod.make(range: .month, offset: 0, now: now)
        XCTAssertEqual(rolling.title, "Son 30 gün")
    }

    // MARK: Rapor metni

    func testChangeAndSummaryText() {
        let period = HistoryReportPeriod.make(range: .day, offset: 1, now: date("2027-03-15"))
        var report = HistoryReport(period: period, mobile: 1_000_000, other: 9_000_000, previousTotal: 20_000_000,
                                   apps: [HistoryAppBytes(app: "/Applications/Foo.app", bytes: 6_000_000, mobile: 0)],
                                   domains: [HistoryDomainBytes(name: "YouTube", bytes: 3_000_000)], attributed: 6_000_000)
        XCTAssertEqual(report.changeText, "-%50")
        XCTAssertEqual(report.mobileShare, 0.1, accuracy: 0.0001)
        let text = report.summaryText { _ in "Foo" }
        XCTAssertTrue(text.contains("Dün"))
        XCTAssertTrue(text.contains("-%50"))
        XCTAssertTrue(text.contains("1. Foo"))
        XCTAssertTrue(text.contains("1. YouTube"))
        report.previousTotal = 0
        XCTAssertNil(report.changeText)
        report.previousTotal = 10_000_000
        XCTAssertEqual(report.changeText, "%0")
    }
}
