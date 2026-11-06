import XCTest
@testable import Adalmon

final class UsageStoreHourlyTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "usage-hourly-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func makeStore() -> UsageStore { UsageStore(path: dir.appending(path: "t.sqlite").path) }

    private let h0 = 1_800_000_000 / 3600 * 3600
    private func row(_ hourOffset: Int, _ app: String, _ domain: String?, mobile: Bool, _ inB: UInt64, _ outB: UInt64 = 0) -> UsageStore.HourlyRow {
        UsageStore.HourlyRow(hour: h0 + hourOffset * 3600, app: app, domain: domain, mobile: mobile, bytesIn: inB, bytesOut: outB)
    }

    func testHourlyRoundTripMergesDuplicatesIncludingNilDomain() async {
        let s = makeStore()
        await s.add(day: "2027-01-15", rows: [], hourly: [
            row(0, "A", "YouTube", mobile: true, 100, 10), row(0, "A", nil, mobile: true, 5), row(0, "B", nil, mobile: false, 7),
        ])
        // İkinci yazma aynı anahtarlara eklenir (NULL domain satırları çoğalmaz).
        await s.add(day: "2027-01-15", rows: [], hourly: [row(0, "A", "YouTube", mobile: true, 1, 1), row(0, "A", nil, mobile: true, 5)])
        let all = await s.allHourlyRows()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.first { $0.app == "A" && $0.domain == "YouTube" }, row(0, "A", "YouTube", mobile: true, 101, 11))
        XCTAssertEqual(all.first { $0.app == "A" && $0.domain == nil }?.bytesIn, 10)
    }

    func testHourlySeriesTotalsAndTopApps() async {
        let s = makeStore()
        await s.add(day: "d", rows: [], hourly: [
            row(0, "A", "x", mobile: true, 100), row(0, "A", "y", mobile: false, 50), row(0, "B", nil, mobile: true, 30),
            row(1, "A", "x", mobile: true, 10), row(3, "A", "x", mobile: true, 999),
        ])
        await s.addInterfaceHourly([(hour: h0, mobile: 200, other: 60), (hour: h0 + 3600, mobile: 11, other: 0)])

        let series = await s.hourlySeries(app: "A", from: h0, to: h0 + 3 * 3600)
        XCTAssertEqual(series, [UsageStore.HourPoint(hour: h0, mobileBytes: 100, otherBytes: 50),
                                UsageStore.HourPoint(hour: h0 + 3600, mobileBytes: 10, otherBytes: 0)])
        let total = await s.appsHourlyTotal(from: h0, to: h0 + 3 * 3600)
        XCTAssertEqual(total.first, UsageStore.HourPoint(hour: h0, mobileBytes: 130, otherBytes: 50))
        // Arayüz serisi uygulama toplamından bağımsızdır ve `__iface__` uygulama listelerine karışmaz.
        let iface = await s.interfaceHourly(from: h0, to: h0 + 3 * 3600)
        XCTAssertEqual(iface, [UsageStore.HourPoint(hour: h0, mobileBytes: 200, otherBytes: 60),
                               UsageStore.HourPoint(hour: h0 + 3600, mobileBytes: 11, otherBytes: 0)])
        let top = await s.topApps(hour: h0, limit: 5)
        XCTAssertEqual(top.map(\.app), ["A", "B"])
        XCTAssertEqual(top.first, UsageStore.AppHourBytes(app: "A", bytes: 150, mobileBytes: 100))
        let doms = await s.hourlyDomains(app: "B", hour: h0)
        XCTAssertEqual(doms.count, 1)
        XCTAssertNil(doms.first?.domain)
    }

    func testPruneRemovesRowsOlderThanSixtyDays() async {
        let s = makeStore()
        let now = Date(timeIntervalSince1970: TimeInterval(h0))
        let old = h0 - 61 * 86_400
        let keep = h0 - 59 * 86_400
        await s.add(day: "d", rows: [], hourly: [
            UsageStore.HourlyRow(hour: old, app: "A", domain: nil, mobile: true, bytesIn: 1, bytesOut: 0),
            UsageStore.HourlyRow(hour: keep, app: "A", domain: nil, mobile: true, bytesIn: 2, bytesOut: 0),
        ])
        await s.pruneHourly(now: now)
        let all = await s.allHourlyRows()
        XCTAssertEqual(all.map(\.hour), [keep])
    }

    func testDailySeriesCycleSumAndTopDomains() async {
        let s = makeStore()
        await s.add(day: "2027-01-10", rows: [
            .init(app: "A", host: "rr1.googlevideo.com", mobile: true, bytesIn: 100, bytesOut: 0),
            .init(app: "A", host: "i.ytimg.com", mobile: true, bytesIn: 50, bytesOut: 0),
            .init(app: "A", host: "cdn.example.org", mobile: false, bytesIn: 30, bytesOut: 0),
        ])
        await s.add(day: "2027-01-11", rows: [.init(app: "A", host: "cdn.example.org", mobile: true, bytesIn: 7, bytesOut: 1)])
        await s.addInterfaceBytes(day: "2027-01-10", mobile: true, bytes: 500)
        await s.addInterfaceBytes(day: "2027-01-10", mobile: false, bytes: 40)
        await s.addInterfaceBytes(day: "2027-01-11", mobile: true, bytes: 300)
        await s.addInterfaceBytes(day: "2027-01-12", mobile: true, bytes: 9)

        let appDays = await s.dailySeries(app: "A", fromDay: "2027-01-09", toDay: "2027-01-12")
        XCTAssertEqual(appDays, [UsageStore.DayPoint(day: "2027-01-10", mobileBytes: 150, otherBytes: 30),
                                 UsageStore.DayPoint(day: "2027-01-11", mobileBytes: 8, otherBytes: 0)])
        let totals = await s.dailyTotals(fromDay: "2027-01-10", toDay: "2027-01-11")
        XCTAssertEqual(totals, [UsageStore.DayPoint(day: "2027-01-10", mobileBytes: 500, otherBytes: 40),
                                UsageStore.DayPoint(day: "2027-01-11", mobileBytes: 300, otherBytes: 0)])
        let cycle = await s.interfaceBytes(fromDay: "2027-01-10", toDay: "2027-01-11", mobile: true)
        XCTAssertEqual(cycle, 800)
        let empty = await s.interfaceBytes(fromDay: "2027-01-12", toDay: "2027-01-11", mobile: true) // dönemin ilk günü
        XCTAssertEqual(empty, 0)
        let domains = await s.topDomains(app: "A", fromDay: "2027-01-10", toDay: "2027-01-11", limit: 5)
        XCTAssertEqual(domains.first, UsageStore.DomainBytes(name: "YouTube", bytes: 150))
        XCTAssertEqual(domains.count, 2)
    }

    @MainActor
    func testEngineFlushWritesHourlyRowsWithGroupedDomain() async throws {
        let store = makeStore()
        let engine = UsageEngine(store: store)
        let now = Date(timeIntervalSince1970: TimeInterval(h0 + 120))
        let b = { (host: String, bytes: UInt64, kind: FlowKind) in
            UsageBucket(app: "/Applications/A.app", signingID: "", host: host, kind: kind, expensive: true,
                        minute: Int(now.timeIntervalSince1970 / 60), bytesIn: bytes, bytesOut: 0)
        }
        engine.ingest([b("rr1.googlevideo.com", 100, .direct), b("rr2.googlevideo.com", 50, .direct), b("", 5, .direct), b("1.2.3.4", 999, .proxyEgress)], now: now)
        await engine.flush()
        let rows = await store.allHourlyRows()
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first { $0.domain == "YouTube" }?.bytesIn, 150)
        XCTAssertEqual(rows.first { $0.domain == nil }?.bytesIn, 5)
        XCTAssertEqual(rows.first?.hour, h0)
    }

    @MainActor
    func testEngineRollsDayAtLocalMidnightNotGMT() async throws {
        let store = makeStore()
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let engine = UsageEngine(store: store, calendar: berlin)
        func bucket(_ at: Date, _ bytes: UInt64) -> UsageBucket {
            UsageBucket(app: "/Applications/A.app", signingID: "", host: "x.example.com", kind: .direct, expensive: true,
                        minute: Int(at.timeIntervalSince1970 / 60), bytesIn: bytes, bytesOut: 0)
        }
        // 28 Mart 23:30 Berlin (22:30Z), sonra 29 Mart 00:30 Berlin (23:30Z; GMT günü hâlâ 28). Aralarında DST günü başlıyor.
        let before = Date(timeIntervalSince1970: 1_774_737_000) // 2026-03-28T22:30:00Z
        let after = before.addingTimeInterval(3600)
        engine.ingest([bucket(before, 10)], now: before)
        await engine.flush()
        engine.ingest([bucket(after, 7)], now: after)
        await engine.flush()
        let d28 = await store.rows(day: "2026-03-28")
        let d29 = await store.rows(day: "2026-03-29")
        XCTAssertEqual(d28.map { $0.bytesIn }, [10])
        XCTAssertEqual(d29.map { $0.bytesIn }, [7])
        XCTAssertEqual(engine.attributedMobileToday, 7) // gün sıfırlandı
    }

    func testTrafficTrackerRateAndHourlyDrain() async {
        let start = Date(timeIntervalSince1970: TimeInterval(h0))
        let tracker = await TrafficTracker(startedAt: start)
        await MainActor.run {
            for i in 0..<15 { tracker.add(bytes: 60_000, mobile: true, at: start.addingTimeInterval(Double(i) * 60 + 5)) }
            tracker.add(bytes: 1, mobile: false, at: start.addingTimeInterval(10))
            // 15 dk * 60 KB = 900 KB; geçen süre 14 dk 30 sn = 870 sn → ~1034 B/sn.
            let rate = tracker.recentMobileRate(now: start.addingTimeInterval(14 * 60 + 30))
            XCTAssertEqual(rate, 900_000 / 870, accuracy: 1)
            let drained = tracker.drainHourly()
            XCTAssertEqual(drained.count, 1)
            XCTAssertEqual(drained[0].mobile, 900_000)
            XCTAssertEqual(drained[0].other, 1)
            XCTAssertTrue(tracker.drainHourly().isEmpty)
        }
    }
}
