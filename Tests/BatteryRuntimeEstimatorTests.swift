import XCTest
@testable import Adalmon

final class BatteryRuntimeEstimatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    private func reading(at s: TimeInterval = 0, level: Int = 50, maxMAh: Int? = 5000, amps: Int? = -1000,
                         plugged: Bool = false, charging: Bool = false) -> BatteryReading {
        var r = BatteryReading()
        r.timestamp = t0.addingTimeInterval(s)
        r.level = level
        r.rawMaxMAh = maxMAh
        r.amperageMA = amps
        r.isPluggedIn = plugged
        r.isCharging = charging
        return r
    }

    func testSingleSampleGivesInstantEstimate() {
        var e = BatteryRuntimeEstimator()
        let r = reading()
        e.record(r)
        XCTAssertEqual(e.minutes(for: r), 150, "5000 mAh × %50 = 2500 mAh ÷ 1000 mA = 2,5 sa")
    }

    func testAveragesOverTheWindowByTime() {
        var e = BatteryRuntimeEstimator()
        for (i, ma) in [-1000, -1000, -2000, -2000].enumerated() { e.record(reading(at: Double(i) * 60, amps: ma)) }
        let last = reading(at: 180, amps: -2000)
        let avg = e.averageDrawMA()
        XCTAssertNotNil(avg)
        XCTAssertGreaterThan(avg!, 1000)
        XCTAssertLessThan(avg!, 2000)
        XCTAssertLessThan(e.minutes(for: last)!, 150, "tüketim artınca süre kısalır")
    }

    func testHeavyLoadShortensTheEstimateQuickly() {
        var e = BatteryRuntimeEstimator()
        e.record(reading(at: 0, amps: -500))
        let before = e.minutes(for: reading(at: 0, amps: -500))!
        e.record(reading(at: 5, amps: -3000))
        e.record(reading(at: 10, amps: -3000))
        XCTAssertLessThan(e.minutes(for: reading(at: 10, amps: -3000))!, before)
    }

    func testOldSamplesLeaveTheWindow() {
        var e = BatteryRuntimeEstimator()
        e.record(reading(at: 0, amps: -4000))
        e.record(reading(at: 400, amps: -1000))
        XCTAssertEqual(e.sampleCount, 1, "5 dk'dan eski örnek atılır")
        XCTAssertEqual(e.averageDrawMA(), 1000)
    }

    func testNoEstimateWhenPluggedChargingOrIdleDraw() {
        var e = BatteryRuntimeEstimator()
        e.record(reading(amps: -1000))
        XCTAssertNil(e.minutes(for: reading(plugged: true)))
        XCTAssertNil(e.minutes(for: reading(charging: true)))
        e.record(reading(at: 10, plugged: true))
        XCTAssertEqual(e.sampleCount, 0, "fişe takılınca pencere sıfırlanır")
        e.record(reading(at: 20, amps: -10))
        XCTAssertNil(e.minutes(for: reading(at: 20, amps: -10)), "40 mA altı: anlamsız")
        e.record(reading(at: 30, amps: 500))
        XCTAssertEqual(e.sampleCount, 0, "pozitif akım deşarj değil")
    }

    func testFallsBackToRawCurrentAndCapsAtTwoDays() {
        var e = BatteryRuntimeEstimator()
        let r = reading(level: 80, maxMAh: nil, amps: -50)
        var raw = r; raw.rawCurrentMAh = 4000
        e.record(raw)
        XCTAssertEqual(e.minutes(for: raw), 2880, "4000 mAh ÷ 50 mA = 80 sa: 48 sa üst sınırı")
        XCTAssertNil(BatteryRuntimeEstimator.remainingMAh(reading(level: 0)), "seviye 0 ve ham kapasite yok")
    }

    func testFormatShowsApproxOnlyForOwnEstimate() {
        var r = reading()
        r.timeToEmptyMinutes = 150
        XCTAssertEqual(BatteryFormat.statusLine(r), "Pil · 2 sa 30 dk kaldı")
        r.timeToEmptyIsEstimate = true
        XCTAssertEqual(BatteryFormat.statusLine(r), "Pil · ≈2 sa 30 dk kaldı")
    }

    @MainActor
    func testMonitorPrefersOwnEstimateThenFallsBack() {
        var system = reading(amps: -1000)
        system.timeToEmptyMinutes = 999
        let monitor = BatteryMonitor(store: nil, readProvider: { system })
        monitor.start()
        defer { monitor.stop() }   // IOPS kaynağı çözülmüş işaretçi tutar: durdurulmazsa sonraki testte çöker
        XCTAssertEqual(monitor.reading?.timeToEmptyMinutes, 150)
        XCTAssertEqual(monitor.reading?.timeToEmptyIsEstimate, true)
    }
}
