import XCTest
@testable import Adalmon

/// USAGE-02: tüketim hızından dolma tahmini ve pencere başına tek uyarı. Saf mantık; zamanlayıcı ve gerçek dosya yok.
final class LimitForecastTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let minute: TimeInterval = 60, hour: TimeInterval = 3600

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "tr_TR")
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }

    private func claude(five: Double? = nil, week: Double? = nil, fiveReset: Date? = nil, weekReset: Date? = nil, at time: Date) -> ProviderLimits {
        ProviderLimits(source: .claude,
                       fiveHour: five.map { LimitWindow(usedPercent: $0, resetsAt: fiveReset) },
                       weekly: week.map { LimitWindow(usedPercent: $0, resetsAt: weekReset) },
                       observedAt: time)
    }

    func testSteadyHighRateWarnsOnceAndShowsForecast() {
        var engine = LimitForecastEngine()
        let reset = t0.addingTimeInterval(4 * hour)
        var alerts: [LimitForecastAlert] = []
        // 40 → 60 in 20 minutes: 1 point/min, fills at 100 about 40 min later (well before reset in 4 h).
        for (i, used) in [40.0, 45, 50, 55, 60].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 5 * minute)
            alerts += engine.ingest(claude(five: used, fiveReset: reset, at: time), sensitivity: .medium, alertsEnabled: true, now: time)
        }
        XCTAssertEqual(alerts.count, 1)
        let alert = try! XCTUnwrap(alerts.first)
        XCTAssertEqual(alert.kind, .fiveHour)
        XCTAssertEqual(alert.forecast.fillsAt.timeIntervalSince(t0.addingTimeInterval(60 * minute)), 0, accuracy: 1)
        XCTAssertEqual(alert.forecast.ratePerHour, 60, accuracy: 0.01)
        // Further rising samples in the same window do not warn again.
        for i in 5..<8 {
            let time = t0.addingTimeInterval(Double(i) * 5 * minute)
            XCTAssertTrue(engine.ingest(claude(five: 60 + Double(i - 4) * 5, fiveReset: reset, at: time), sensitivity: .medium,
                                        alertsEnabled: true, now: time).isEmpty)
        }
        let now = t0.addingTimeInterval(36 * minute)
        XCTAssertNotNil(engine.forecast(.claude, .fiveHour, sensitivity: .medium, now: now))
        // Past the projected fill time the card line disappears.
        XCTAssertNil(engine.forecast(.claude, .fiveHour, sensitivity: .medium, now: t0.addingTimeInterval(2 * hour)))
        // Title and body text.
        XCTAssertEqual(alert.title(), "Claude 5 saatlik limit yenilenmeden dolabilir")
        XCTAssertTrue(alert.body(now: t0, calendar: calendar).hasPrefix("Bu hızla 5 saatlik limit ~"))
        XCTAssertTrue(alert.body(now: t0, calendar: calendar).contains("(şu an %50)"))
    }

    func testLowUsageDoesNotWarnButCardCanShow() {
        var engine = LimitForecastEngine()
        let reset = t0.addingTimeInterval(4 * hour + 30 * minute)
        var alerts: [LimitForecastAlert] = []
        // 10 → 30 in 40 min (30 pts/h): fills ~2 h 20 min later, before reset, but usage is below 50%.
        for (i, used) in [10.0, 15, 20, 25, 30].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 10 * minute)
            alerts += engine.ingest(claude(five: used, fiveReset: reset, at: time), sensitivity: .medium, alertsEnabled: true, now: time)
        }
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertNotNil(engine.forecast(.claude, .fiveHour, sensitivity: .medium, now: t0.addingTimeInterval(40 * minute)))
        // High sensitivity does not lower the usage floor below 35%: still no warning at 30%.
        var high = LimitForecastEngine()
        var highAlerts: [LimitForecastAlert] = []
        for (i, used) in [10.0, 15, 20, 25, 30].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 10 * minute)
            highAlerts += high.ingest(claude(five: used, fiveReset: reset, at: time), sensitivity: .high, alertsEnabled: true, now: time)
        }
        XCTAssertTrue(highAlerts.isEmpty)
    }

    func testFillAfterResetOrSmallMarginDoesNotWarn() {
        var engine = LimitForecastEngine()
        // 60 → 64 in 20 min (12 pts/h): fills in 3 h, reset in 1 h → no forecast at all.
        let reset = t0.addingTimeInterval(80 * minute)
        for (i, used) in [60.0, 62, 64].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 10 * minute)
            XCTAssertTrue(engine.ingest(claude(five: used, fiveReset: reset, at: time), sensitivity: .high, alertsEnabled: true, now: time).isEmpty)
        }
        XCTAssertNil(engine.forecast(.claude, .fiveHour, sensitivity: .medium, now: t0.addingTimeInterval(20 * minute)))

        // Fills 40 min before reset: below the 45 min (Orta) margin, no warning.
        var close = LimitForecastEngine()
        let closeReset = t0.addingTimeInterval(80 * minute)   // 60 pts/h: last sample at +20, fills at +40
        for (i, used) in [60.0, 70, 80].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 10 * minute)
            XCTAssertTrue(close.ingest(claude(five: used, fiveReset: closeReset, at: time), sensitivity: .medium, alertsEnabled: true, now: time).isEmpty)
        }
    }

    func testInsufficientDataDoesNotWarn() {
        // Two samples only.
        var engine = LimitForecastEngine()
        let reset = t0.addingTimeInterval(4 * hour)
        for (i, used) in [60.0, 75].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 10 * minute)
            XCTAssertTrue(engine.ingest(claude(five: used, fiveReset: reset, at: time), sensitivity: .medium, alertsEnabled: true, now: time).isEmpty)
        }
        // Three samples but spanning only 6 minutes.
        var short = LimitForecastEngine()
        for (i, used) in [60.0, 65, 70].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 3 * minute)
            XCTAssertTrue(short.ingest(claude(five: used, fiveReset: reset, at: time), sensitivity: .medium, alertsEnabled: true, now: time).isEmpty)
        }
        XCTAssertNil(short.forecast(.claude, .fiveHour, sensitivity: .medium, now: t0.addingTimeInterval(6 * minute)))
        // Same observedAt re-read (Codex) does not add samples.
        var codex = LimitForecastEngine()
        let same = ProviderLimits(source: .codex, fiveHour: LimitWindow(usedPercent: 60, resetsAt: reset), observedAt: t0)
        for i in 0..<5 {
            _ = codex.ingest(same, sensitivity: .medium, alertsEnabled: true, now: t0.addingTimeInterval(Double(i) * 3 * minute))
        }
        XCTAssertEqual(codex.history(.codex, .fiveHour)?.samples.count, 1)
        // Unknown reset time: no forecast.
        var unknown = LimitForecastEngine()
        for (i, used) in [60.0, 70, 80].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 10 * minute)
            XCTAssertTrue(unknown.ingest(claude(five: used, at: time), sensitivity: .high, alertsEnabled: true, now: time).isEmpty)
        }
        // Alerts disabled or stale data: no warning.
        var disabled = LimitForecastEngine()
        for (i, used) in [50.0, 60, 70].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 10 * minute)
            XCTAssertTrue(disabled.ingest(claude(five: used, fiveReset: reset, at: time), sensitivity: .medium, alertsEnabled: false, now: time).isEmpty)
        }
    }

    func testWindowResetClearsHistoryAndAllowsNewWarning() {
        var engine = LimitForecastEngine()
        let reset1 = t0.addingTimeInterval(4 * hour)
        var alerts: [LimitForecastAlert] = []
        for (i, used) in [50.0, 60, 70].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 10 * minute)
            alerts += engine.ingest(claude(five: used, fiveReset: reset1, at: time), sensitivity: .medium, alertsEnabled: true, now: time)
        }
        XCTAssertEqual(alerts.count, 1)
        // New window: resets_at moves 5 h later → history starts over with a single sample.
        let start2 = reset1.addingTimeInterval(minute)
        let reset2 = reset1.addingTimeInterval(5 * hour)
        XCTAssertTrue(engine.ingest(claude(five: 2, fiveReset: reset2, at: start2), sensitivity: .medium, alertsEnabled: true, now: start2).isEmpty)
        XCTAssertEqual(engine.history(.claude, .fiveHour)?.samples.count, 1)
        // A noticeable drop also clears (reset time unknown or unchanged).
        var history = LimitHistory()
        history.add(LimitWindow(usedPercent: 70, resetsAt: nil), at: t0)
        history.add(LimitWindow(usedPercent: 72, resetsAt: nil), at: t0.addingTimeInterval(minute))
        history.add(LimitWindow(usedPercent: 3, resetsAt: nil), at: t0.addingTimeInterval(2 * minute))
        XCTAssertEqual(history.samples.map(\.usedPercent), [3])
        // The new window can warn again.
        alerts = []
        for (i, used) in [50.0, 60, 70].enumerated() {
            let time = start2.addingTimeInterval(Double(i + 1) * 10 * minute)
            alerts += engine.ingest(claude(five: used, fiveReset: reset2, at: time), sensitivity: .medium, alertsEnabled: true, now: time)
        }
        XCTAssertEqual(alerts.count, 1)
        // Sample cap.
        var capped = LimitHistory()
        for i in 0..<(LimitHistory.maxSamples + 10) {
            capped.add(LimitWindow(usedPercent: Double(i) * 0.1, resetsAt: reset1), at: t0.addingTimeInterval(Double(i) * minute))
        }
        XCTAssertEqual(capped.samples.count, LimitHistory.maxSamples)
    }

    func testWeeklyWarnsWithDayAndTime() {
        var engine = LimitForecastEngine()
        let reset = t0.addingTimeInterval(4 * 24 * hour)
        var alerts: [LimitForecastAlert] = []
        // 40 → 52 in 4 h (3 pts/h): fills in 16 h, reset in ~4 days.
        for (i, used) in [40.0, 44, 48, 52].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 80 * minute)
            alerts += engine.ingest(claude(week: used, weekReset: reset, at: time), sensitivity: .medium, alertsEnabled: true, now: time)
        }
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.kind, .weekly)
        // Spanning under 2 h is not enough for weekly.
        var short = LimitForecastEngine()
        for (i, used) in [40.0, 44, 48].enumerated() {
            let time = t0.addingTimeInterval(Double(i) * 30 * minute)
            XCTAssertTrue(short.ingest(claude(week: used, weekReset: reset, at: time), sensitivity: .medium, alertsEnabled: true, now: time).isEmpty)
        }
        // Text: 2027-01-15 08:00 UTC = 11:00 Istanbul, Friday.
        let fill = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00:00 UTC
        let forecast = LimitForecast(fillsAt: fill, resetsAt: fill.addingTimeInterval(2 * 24 * hour + 30 * minute),
                                     ratePerHour: 3, usedPercent: 52, basedOn: fill)
        let monday = fill.addingTimeInterval(-4 * 24 * hour)
        let body = LimitForecastAlert(source: .codex, kind: .weekly, forecast: forecast).body(now: monday, calendar: calendar)
        XCTAssertEqual(body, "Bu hızla haftalık limit ~Cuma 11:00'de dolacak, yenilenme Pazar 11:30 (şu an %52).")
        XCTAssertEqual(LimitForecastFormat.moment(fill, kind: .weekly, now: fill.addingTimeInterval(-hour), calendar: calendar), "bugün 11:00")
        XCTAssertEqual(LimitForecastFormat.moment(fill, kind: .weekly, now: fill.addingTimeInterval(-24 * hour), calendar: calendar), "yarın 11:00")
    }

    func testLocativeSuffix() {
        let cases: [(Int, String)] = [(20, "'de"), (30, "'da"), (40, "'ta"), (10, "'da"), (50, "'de"), (14, "'te"), (12, "'de"),
                                      (0, "'da"), (1, "'de"), (3, "'te"), (5, "'te"), (6, "'da"), (9, "'da"), (23, "'te"), (17, "'de")]
        for (n, suffix) in cases { XCTAssertEqual(LimitForecastFormat.locativeSuffix(number: n), suffix, "\(n)") }
        func at(_ h: Int, _ m: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: h, minute: m))!
        }
        XCTAssertEqual(LimitForecastFormat.locativeSuffix(at(14, 0), calendar: calendar), "'te")
        XCTAssertEqual(LimitForecastFormat.locativeSuffix(at(12, 0), calendar: calendar), "'de")
        XCTAssertEqual(LimitForecastFormat.locativeSuffix(at(14, 20), calendar: calendar), "'de")
        XCTAssertEqual(LimitForecastFormat.locativeSuffix(at(14, 40), calendar: calendar), "'ta")
    }

    @MainActor func testModelPersistsForecastWarningAndSensitivity() throws {
        let suite = "adalmon-forecast-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let temp = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temp) }
        let binder = ClaudeStatusLineBinder(settingsURL: temp.appending(path: "claude/settings.json"),
                                            supportDirectory: temp.appending(path: "support", directoryHint: .isDirectory),
                                            configURL: temp.appending(path: "config.json"))
        let model = SubscriptionLimitsModel(defaults: defaults, binder: binder, codexReader: CodexRolloutReader(root: temp), live: false)
        XCTAssertEqual(model.forecastSensitivity, .medium)
        var sent: [String] = []
        model.notify = { title, _ in sent.append(title) }
        let now = Date.now
        let reset = now.addingTimeInterval(4 * hour)
        for (i, used) in [50.0, 60, 70].enumerated() {
            let time = now.addingTimeInterval(Double(i - 2) * 10 * minute)
            model.ingestClaude(claude(five: used, fiveReset: reset, at: time), now: time)
        }
        XCTAssertEqual(sent.filter { $0.contains("yenilenmeden dolabilir") }.count, 1)
        XCTAssertNotNil(model.forecast(for: try XCTUnwrap(model.claude), .fiveHour, now: now))
        model.forecastSensitivity = .low
        // A relaunch keeps the "warned" record and the sensitivity; the same window does not warn again.
        let reloaded = SubscriptionLimitsModel(defaults: defaults, binder: binder, codexReader: CodexRolloutReader(root: temp), live: false)
        XCTAssertEqual(reloaded.forecastSensitivity, .low)
        reloaded.forecastSensitivity = .medium
        var again: [String] = []
        reloaded.notify = { title, _ in again.append(title) }
        for (i, used) in [72.0, 74, 76].enumerated() {
            let time = now.addingTimeInterval(Double(i + 1) * 10 * minute)
            reloaded.ingestClaude(claude(five: used, fiveReset: reset, at: time), now: time)
        }
        XCTAssertTrue(again.filter { $0.contains("yenilenmeden dolabilir") }.isEmpty)
    }

    /// Claude values arrive often (every change): one sample per minute for 3 h must still give the weekly window enough span.
    func testDenseSamplesStillReachWeeklySpanAndWarnOnce() {
        var engine = LimitForecastEngine()
        let fiveReset = t0.addingTimeInterval(4 * hour + 50 * minute)
        let weekReset = t0.addingTimeInterval(3 * 24 * hour)
        var alerts: [LimitForecastAlert] = []
        for i in 0...180 {
            let time = t0.addingTimeInterval(Double(i) * minute)
            // Weekly rises 3 pts/h from 45; five-hour stays low (10 → 19), so only weekly warns.
            let limits = claude(five: 10 + Double(i) * 0.05, week: 45 + Double(i) * 0.05,
                                fiveReset: fiveReset, weekReset: weekReset, at: time)
            alerts += engine.ingest(limits, sensitivity: .medium, alertsEnabled: true, now: time)
            XCTAssertLessThanOrEqual(engine.history(.claude, .weekly)?.samples.count ?? 0, LimitHistory.maxSamples)
            XCTAssertLessThanOrEqual(engine.history(.claude, .fiveHour)?.samples.count ?? 0, LimitHistory.maxSamples)
        }
        XCTAssertEqual(alerts.map(\.kind), [.weekly])
        let rate = try! XCTUnwrap(alerts.first).forecast.ratePerHour
        XCTAssertEqual(rate, 3, accuracy: 0.01)
    }

    func testDenseFiveHourSamplesWarnOnce() {
        var engine = LimitForecastEngine()
        let reset = t0.addingTimeInterval(4 * hour)
        var alerts: [LimitForecastAlert] = []
        // Every 20 s for 40 min, 40 → 80 (60 pts/h).
        for i in 0...120 {
            let time = t0.addingTimeInterval(Double(i) * 20)
            alerts += engine.ingest(claude(five: 40 + Double(i) / 3, fiveReset: reset, at: time), sensitivity: .medium, alertsEnabled: true, now: time)
        }
        XCTAssertEqual(alerts.count, 1)
        XCTAssertLessThanOrEqual(engine.history(.claude, .fiveHour)?.samples.count ?? 0, LimitHistory.maxSamples)
        XCTAssertEqual(try! XCTUnwrap(alerts.first).forecast.ratePerHour, 60, accuracy: 0.5)
    }
}
