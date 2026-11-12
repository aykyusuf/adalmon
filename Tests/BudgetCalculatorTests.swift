import XCTest
@testable import Adalmon

final class BudgetCalculatorTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "GMT")!
        return c
    }()
    private let GB: UInt64 = 1_000_000_000

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Dönem başlangıcı

    func testCycleStartBeforeAndOnAndAfterStartDay() {
        // Başlangıç günü 14: bugün 20'si → bu ayın 14'ü.
        XCTAssertEqual(BudgetCalculator.cycleStart(containing: date(2026, 11, 20, 15), startDay: 14, calendar: cal), date(2026, 11, 14))
        // Bugün tam 14'ü → bugün.
        XCTAssertEqual(BudgetCalculator.cycleStart(containing: date(2026, 11, 14, 0, 1), startDay: 14, calendar: cal), date(2026, 11, 14))
        // Başlangıç günü bugünden büyük (5'i < 14) → geçen ayın 14'ü.
        XCTAssertEqual(BudgetCalculator.cycleStart(containing: date(2026, 11, 5), startDay: 14, calendar: cal), date(2026, 10, 14))
        // Yıl başı: 3 Ocak, başlangıç 14 → geçen yılın 14 Aralık'ı.
        XCTAssertEqual(BudgetCalculator.cycleStart(containing: date(2027, 1, 3), startDay: 14, calendar: cal), date(2026, 12, 14))
    }

    func testCycleStartDay31InShortMonthsClampsToLastDay() {
        XCTAssertEqual(BudgetCalculator.cycleStart(containing: date(2026, 2, 28, 12), startDay: 31, calendar: cal), date(2026, 2, 28))
        XCTAssertEqual(BudgetCalculator.cycleStart(containing: date(2026, 2, 27), startDay: 31, calendar: cal), date(2026, 1, 31))
        XCTAssertEqual(BudgetCalculator.cycleStart(containing: date(2026, 3, 15), startDay: 31, calendar: cal), date(2026, 2, 28))
        XCTAssertEqual(BudgetCalculator.cycleStart(containing: date(2026, 5, 1), startDay: 31, calendar: cal), date(2026, 4, 30))
        // Artık yıl.
        XCTAssertEqual(BudgetCalculator.cycleStart(containing: date(2028, 3, 10), startDay: 31, calendar: cal), date(2028, 2, 29))
        XCTAssertEqual(BudgetCalculator.nextCycleStart(after: date(2026, 1, 31), startDay: 31, calendar: cal), date(2026, 2, 28))
        XCTAssertEqual(BudgetCalculator.nextCycleStart(after: date(2026, 2, 28), startDay: 31, calendar: cal), date(2026, 3, 31))
        XCTAssertEqual(BudgetCalculator.nextCycleStart(after: date(2026, 12, 14), startDay: 14, calendar: cal), date(2027, 1, 14))
    }

    func testDayKeyFormat() {
        XCTAssertEqual(BudgetCalculator.dayKey(date(2026, 3, 5, 23, 59), calendar: cal), "2026-03-05")
        XCTAssertEqual(UsageStore.dayKey(date(2026, 3, 5, 23, 59), calendar: cal), "2026-03-05") // calendar ile aynı biçim
    }

    // MARK: Yerel gün (GMT değil)

    private func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date { date(y, m, d, h, min) }

    func testDayKeyUsesInjectedLocalTimeZone() {
        let istanbul = calendar("Europe/Istanbul") // UTC+3 sabit
        // 21:30Z = İstanbul 00:30 ertesi gün: yerel gün değişmiş, GMT günü değişmemiş.
        let t = utc(2026, 11, 5, 21, 30)
        XCTAssertEqual(UsageStore.dayKey(t, calendar: istanbul), "2026-11-06")
        XCTAssertEqual(UsageStore.dayKey(t, calendar: cal), "2026-11-05")
        XCTAssertEqual(UsageStore.dayKey(utc(2026, 11, 5, 20, 59), calendar: istanbul), "2026-11-05")
        // Yerel gece yarısı = günün ilk saniyesi.
        XCTAssertEqual(UsageStore.dayKey(utc(2026, 11, 5, 21, 0), calendar: istanbul), "2026-11-06")
    }

    func testKeyCalendarDefaultsToCurrentTimeZoneAndGregorian() {
        let k = UsageStore.keyCalendar
        XCTAssertEqual(k.identifier, .gregorian)
        XCTAssertEqual(k.timeZone.identifier, TimeZone.current.identifier)
        let now = Date.now
        XCTAssertEqual(UsageStore.dayKey(now), UsageStore.dayKey(now, calendar: k))
    }

    func testCycleBoundaryKeysAreLocalMidnights() {
        let berlin = calendar("Europe/Berlin")
        let now = berlin.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))!
        let start = BudgetCalculator.cycleStart(containing: now, startDay: 14, calendar: berlin)
        XCTAssertEqual(start, berlin.date(from: DateComponents(year: 2026, month: 3, day: 14))!)
        XCTAssertEqual(UsageStore.dayKey(start, calendar: berlin), "2026-03-14") // GMT'de 13'ü olurdu
        let next = BudgetCalculator.nextCycleStart(after: start, startDay: 14, calendar: berlin)
        XCTAssertEqual(UsageStore.dayKey(next, calendar: berlin), "2026-04-14") // DST geçişini aşan dönem
    }

    func testSpringForwardDayIs23HoursAndEndOfDayIsLocalMidnight() {
        let berlin = calendar("Europe/Berlin") // 2026-03-29: 02:00 → 03:00
        let now = berlin.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12))!
        // 12:00 yerel → gün sonuna 12 saat (UTC+2'ye geçildi); +86400 ile hesaplanırsa yanlış (13 saat) olurdu.
        func snap(etaHours: Double) -> BudgetSnapshot {
            BudgetCalculator.snapshot(now: now, startDay: 1, monthlyCapBytes: 90 * GB, dailyCapBytes: 1000,
                                      cycleUsedBeforeToday: 0, todayUsed: 0, recentRate: 1000 / (etaHours * 3600), calendar: berlin)
        }
        if case .at = snap(etaHours: 11.5).etaRecentRate {} else { XCTFail("gün içinde dolmalı") }
        XCTAssertEqual(snap(etaHours: 12.5).etaRecentRate, .notToday)
        // Ortalama hız: gün başından 11 gerçek saat geçti (02:00 yok).
        let s = BudgetCalculator.snapshot(now: now, startDay: 1, monthlyCapBytes: nil, dailyCapBytes: 4_000_000,
                                          cycleUsedBeforeToday: 0, todayUsed: 3_960_000, recentRate: 0, calendar: berlin)
        if case .at(let eta) = s.etaAverageRate {
            XCTAssertEqual(eta.timeIntervalSince(now), (4_000_000 - 3_960_000) / (3_960_000 / (11.0 * 3600)), accuracy: 1)
        } else { XCTFail("ortalama hızla gün içinde dolmalı") }
        // Takvim günü sayımı: 29 Mart → 1 Nisan = 3 gün (47 saatlik aralık yine tam günlerle sayılır).
        XCTAssertEqual(s.daysLeft, 3)
    }

    func testFallBackDayIs25HoursAndEndOfDayIsLocalMidnight() {
        let berlin = calendar("Europe/Berlin") // 2026-10-25: 03:00 → 02:00
        let now = berlin.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        func snap(etaHours: Double) -> BudgetSnapshot {
            BudgetCalculator.snapshot(now: now, startDay: 1, monthlyCapBytes: nil, dailyCapBytes: 1000,
                                      cycleUsedBeforeToday: 0, todayUsed: 0, recentRate: 1000 / (etaHours * 3600), calendar: berlin)
        }
        // Gün sonu 00:00 (12 saat sonra); +86400 ile 11 saat olurdu.
        if case .at = snap(etaHours: 11.5).etaRecentRate {} else { XCTFail("gün içinde dolmalı") }
        XCTAssertEqual(snap(etaHours: 12.5).etaRecentRate, .notToday)
    }

    private func hourlyKeys(from start: Date, hours: Int, bytes: UInt64 = 100) -> [Int: UInt64] {
        var m: [Int: UInt64] = [:]
        for i in 0..<hours { m[Int(start.timeIntervalSince1970) + i * 3600] = bytes }
        return m
    }

    func testCumulativeSeriesOnSpringForwardDayHasNoMissingHourGap() {
        let berlin = calendar("Europe/Berlin")
        let dayStart = berlin.date(from: DateComponents(year: 2026, month: 3, day: 29))! // 28.3. 23:00Z
        let now = berlin.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 5))! // 03:00Z
        // Yerel 00-01, 01-02, 03-04, 04-05 → 4 gerçek saat (02:xx yok).
        let pts = BudgetCalculator.cumulativeSeries(hourly: hourlyKeys(from: dayStart, hours: 4), now: now, calendar: berlin)
        XCTAssertEqual(pts.count, 5)
        XCTAssertEqual(pts.first?.date, dayStart)
        XCTAssertEqual(pts.last?.date, now)
        XCTAssertEqual(pts.last?.bytes, 400)
        XCTAssertEqual(pts.map(\.bytes), [0, 100, 200, 300, 400])
    }

    func testCumulativeSeriesOnFallBackDayCountsRepeatedHour() {
        let berlin = calendar("Europe/Berlin")
        let dayStart = berlin.date(from: DateComponents(year: 2026, month: 10, day: 25))! // 24.10. 22:00Z
        let now = berlin.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 4))! // 03:00Z
        // Yerel 02:00-03:00 iki kez yaşanır: 5 gerçek saat.
        let pts = BudgetCalculator.cumulativeSeries(hourly: hourlyKeys(from: dayStart, hours: 5), now: now, calendar: berlin)
        XCTAssertEqual(pts.count, 6)
        XCTAssertEqual(pts.last?.bytes, 500)
    }

    func testCumulativeSeriesHalfHourOffsetZoneUsesLocalHourContainment() {
        let kolkata = calendar("Asia/Kolkata") // UTC+5:30: yerel saat başı epoch saat başıyla hizalı değil
        let dayStart = kolkata.date(from: DateComponents(year: 2026, month: 6, day: 10))! // 9.6. 18:30Z
        let now = kolkata.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 6))!
        // Epoch saat başları 19:00Z...00:00Z (yerel 00:30...05:30) → her biri kendi yerel saatine düşer.
        let pts = BudgetCalculator.cumulativeSeries(hourly: hourlyKeys(from: dayStart.addingTimeInterval(1800), hours: 6),
                                                    now: now, calendar: kolkata)
        XCTAssertEqual(pts.count, 7)
        XCTAssertEqual(pts.last?.bytes, 600)
    }

    // MARK: Bütçe

    func testDynamicDailyBudgetRemainingAndProjection() {
        // Dönem 14 Kasım'da başladı, bugün 20 Kasım 12:00; sonraki dönem 14 Aralık → bugün dahil 24 gün kaldı.
        let now = date(2026, 11, 20, 12)
        let s = BudgetCalculator.snapshot(now: now, startDay: 14, monthlyCapBytes: 30 * GB, dailyCapBytes: 3 * GB,
                                          cycleUsedBeforeToday: 6 * GB, todayUsed: 1 * GB, recentRate: 0, calendar: cal)
        XCTAssertEqual(s.cycleStart, date(2026, 11, 14))
        XCTAssertEqual(s.nextCycleStart, date(2026, 12, 14))
        XCTAssertEqual(s.daysLeft, 24)
        XCTAssertEqual(s.cycleUsedBytes, 7 * GB)
        XCTAssertEqual(s.remainingBytes, 23 * GB)
        XCTAssertEqual(s.dynamicDailyBudgetBytes, 24 * GB / 24) // (30-6)/24 = 1 GB
        XCTAssertEqual(s.effectiveDailyCapBytes, 3 * GB)       // günlük limit esas; tempo yalnızca bilgi
        XCTAssertEqual(s.todayRemainingBytes, 2 * GB)
        // 6 gün geçti → 6 GB / 6 * 30 gün = 30 GB
        XCTAssertEqual(s.projectedCycleBytes, 30 * GB)
    }

    func testNoMonthlyCapUsesDailyCapOnly() {
        let s = BudgetCalculator.snapshot(now: date(2026, 11, 20, 12), startDay: 1, monthlyCapBytes: nil, dailyCapBytes: 3 * GB,
                                          cycleUsedBeforeToday: 0, todayUsed: 1 * GB, recentRate: 0, calendar: cal)
        XCTAssertNil(s.remainingBytes)
        XCTAssertNil(s.dynamicDailyBudgetBytes)
        XCTAssertEqual(s.effectiveDailyCapBytes, 3 * GB)
        XCTAssertEqual(s.todayRemainingBytes, 2 * GB)
    }

    func testOverspentCycleClampsToZeroAndLastDayHasOneDayLeft() {
        let s = BudgetCalculator.snapshot(now: date(2026, 12, 13, 8), startDay: 14, monthlyCapBytes: 10 * GB, dailyCapBytes: 3 * GB,
                                          cycleUsedBeforeToday: 12 * GB, todayUsed: 0, recentRate: 0, calendar: cal)
        XCTAssertEqual(s.daysLeft, 1)
        XCTAssertEqual(s.remainingBytes, 0)
        XCTAssertEqual(s.dynamicDailyBudgetBytes, 0)
        XCTAssertEqual(s.effectiveDailyCapBytes, 3 * GB)
    }

    func testFirstDayOfCycleHasNoProjection() {
        let s = BudgetCalculator.snapshot(now: date(2026, 11, 14, 9), startDay: 14, monthlyCapBytes: 30 * GB, dailyCapBytes: 3 * GB,
                                          cycleUsedBeforeToday: 0, todayUsed: 100_000_000, recentRate: 0, calendar: cal)
        XCTAssertNil(s.projectedCycleBytes)
        XCTAssertEqual(s.daysLeft, 30)
    }

    // MARK: Tahmin (ETA)

    func testETAUsesBothRecentAndAverageRates() {
        // 12:00'de 1 GB kullanıldı (ortalama 1e9/43200 sn ≈ 23 KB/sn); son 15 dk hızı 1 MB/sn.
        let now = date(2026, 11, 20, 12)
        let s = BudgetCalculator.snapshot(now: now, startDay: 1, monthlyCapBytes: nil, dailyCapBytes: 3 * GB,
                                          cycleUsedBeforeToday: 0, todayUsed: 1 * GB, recentRate: 1_000_000, calendar: cal)
        // Kalan 2 GB / 1 MB/sn = 2000 sn.
        XCTAssertEqual(s.etaRecentRate, .at(now.addingTimeInterval(2000)))
        // Ortalama hızla 2e9 / (1e9/43200) = 86400 sn → gün içinde dolmaz.
        XCTAssertEqual(s.etaAverageRate, .notToday)
    }

    /// Aylık bütçe günlük limitten küçükken günlük limit ETA'sı günlük limite, bütçe ETA'sı bütçeye göredir.
    func testBudgetETAIsSeparateFromDailyCapETA() {
        let now = date(2026, 11, 20, 12)
        let s = BudgetCalculator.snapshot(now: now, startDay: 14, monthlyCapBytes: 30 * GB, dailyCapBytes: 3 * GB,
                                          cycleUsedBeforeToday: 6 * GB, todayUsed: 500_000_000, recentRate: 1_000_000, calendar: cal)
        XCTAssertEqual(s.dynamicDailyBudgetBytes, 1 * GB)
        XCTAssertEqual(s.etaRecentRate, .at(now.addingTimeInterval(2500)))        // (3 GB - 0.5 GB) / 1 MB/s
        XCTAssertEqual(s.etaBudgetRecentRate, .at(now.addingTimeInterval(500)))   // (1 GB - 0.5 GB) / 1 MB/s
        let none = BudgetCalculator.snapshot(now: now, startDay: 1, monthlyCapBytes: nil, dailyCapBytes: 3 * GB,
                                             cycleUsedBeforeToday: 0, todayUsed: 0, recentRate: 1, calendar: cal)
        XCTAssertNil(none.etaBudgetRecentRate)
    }

    func testETAEdgeCases() {
        let now = date(2026, 11, 20, 12)
        let end = date(2026, 11, 21)
        XCTAssertEqual(BudgetCalculator.capETA(used: 3 * GB, cap: 3 * GB, rate: 5, now: now, endOfDay: end), .reached)
        XCTAssertEqual(BudgetCalculator.capETA(used: 1, cap: 3 * GB, rate: 0, now: now, endOfDay: end), .noData)
        XCTAssertEqual(BudgetCalculator.capETA(used: 1, cap: 0, rate: 5, now: now, endOfDay: end), .noData)
        XCTAssertEqual(BudgetCalculator.capETA(used: 0, cap: 100, rate: 10, now: now, endOfDay: end), .at(now.addingTimeInterval(10)))
        // Gece yarısından sonra dolacaksa bugün dolmaz.
        XCTAssertEqual(BudgetCalculator.capETA(used: 0, cap: 100_000, rate: 1, now: now, endOfDay: end), .notToday)
    }

    func testCumulativeSeriesForToday() {
        let dayStart = date(2026, 11, 20)
        let h = { (i: Int) in Int(dayStart.addingTimeInterval(Double(i) * 3600).timeIntervalSince1970) }
        let now = date(2026, 11, 20, 2, 30)
        let pts = BudgetCalculator.cumulativeSeries(hourly: [h(0): 100, h(1): 50, h(2): 25, h(5): 999], now: now, calendar: cal)
        XCTAssertEqual(pts.map(\.bytes), [0, 100, 150, 175])
        XCTAssertEqual(pts.first?.date, dayStart)
        XCTAssertEqual(pts.last?.date, now) // kısmi saat `now`'da biter
        XCTAssertEqual(pts[1].date, date(2026, 11, 20, 1))
    }
}
