import XCTest
@testable import Adalmon

@MainActor
final class UptimeFormatterTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(UptimeFormatter.duration(0), "1 dk'dan az")
        XCTAssertEqual(UptimeFormatter.duration(59.9), "1 dk'dan az")
        XCTAssertEqual(UptimeFormatter.duration(60), "1 dk")
        XCTAssertEqual(UptimeFormatter.duration(14 * 60), "14 dk")
        XCTAssertEqual(UptimeFormatter.duration(3600), "1 sa")
        XCTAssertEqual(UptimeFormatter.duration(3 * 3600 + 5 * 60), "3 sa 5 dk")
        XCTAssertEqual(UptimeFormatter.duration(2 * 86400 + 23 * 3600 + 14 * 60 + 30), "2 g 23 sa 14 dk")
        XCTAssertEqual(UptimeFormatter.duration(86400), "1 g")
        XCTAssertEqual(UptimeFormatter.duration(2 * 86400 + 14 * 60), "2 g 14 dk")
        XCTAssertEqual(UptimeFormatter.duration(-5), "1 dk'dan az")
        XCTAssertEqual(UptimeFormatter.duration(.infinity), "1 dk'dan az")
    }

    func testShortDuration() {
        XCTAssertEqual(UptimeFormatter.shortDuration(10), "1 dk'dan az")
        XCTAssertEqual(UptimeFormatter.shortDuration(14 * 60), "14 dk")
        XCTAssertEqual(UptimeFormatter.shortDuration(5 * 3600 + 14 * 60), "5 sa 14 dk")
        XCTAssertEqual(UptimeFormatter.shortDuration(5 * 3600), "5 sa")
        XCTAssertEqual(UptimeFormatter.shortDuration(2 * 86400 + 23 * 3600 + 14 * 60), "2 g 23 sa")
        XCTAssertEqual(UptimeFormatter.shortDuration(3 * 86400), "3 g")
    }

    func testBootStampIsLocalTurkish() {
        let utc = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_793_956_320) // 2026-11-06 09:12 UTC
        XCTAssertEqual(UptimeFormatter.bootStamp(date, timeZone: utc), "6 Kas 09:12")
    }

    func testUptimeClampsClockSkewAndUsesInjectedReader() {
        let boot = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(UptimeFormatter.uptime(since: boot, now: boot.addingTimeInterval(90)), 90)
        XCTAssertEqual(UptimeFormatter.uptime(since: boot, now: boot.addingTimeInterval(-90)), 0)
        let reader = BootTimeReader { boot }
        XCTAssertEqual(reader.read(), boot)
        let model = CPUPanelModel.make(PanelData.metricSample, processes: [], bootTime: boot, now: boot.addingTimeInterval(2 * 86400 + 23 * 3600 + 14 * 60))
        XCTAssertEqual(model.uptimeText, "2 g 23 sa 14 dk")
        XCTAssertTrue(model.bootText?.hasPrefix("Son açılış: ") == true)
        XCTAssertNil(CPUPanelModel.make(PanelData.metricSample, processes: [], bootTime: nil).uptimeText)
    }

    func testSystemBootTimeIsPlausible() throws {
        let boot = try XCTUnwrap(BootTimeReader.system.read())
        XCTAssertLessThan(boot, Date())
        XCTAssertGreaterThan(boot.timeIntervalSince1970, 1_400_000_000)
    }
}
