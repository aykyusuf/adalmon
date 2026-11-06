import XCTest
@testable import Adalmon

@MainActor
final class NetworkInspectorLogicTests: XCTestCase {
    func testColumnSetShrinksWithWidth() {
        XCTAssertEqual(NetworkColumnSet(width: 1_100), .full)
        XCTAssertEqual(NetworkColumnSet(width: 700), .withoutDomains)
        XCTAssertEqual(NetworkColumnSet(width: 470), .withoutDomains)
        XCTAssertEqual(NetworkColumnSet(width: 400), .essential)
        XCTAssertTrue(NetworkColumnSet.full.showsDomains && NetworkColumnSet.full.showsStatus)
        XCTAssertFalse(NetworkColumnSet.withoutDomains.showsDomains)
        XCTAssertTrue(NetworkColumnSet.withoutDomains.showsStatus)
        XCTAssertFalse(NetworkColumnSet.essential.showsStatus)
    }

    /// Bugünün saatlik kayıtları (yerel gün sınırlarıyla) uygulama detayında görünür; kaydı olmayan uygulama için açıklama gösterilir.
    func testAppDetailReadsTodaysHourlyRowsAndExplainsLateStart() async throws {
        let model = AppModel()
        let cal = UsageStore.keyCalendar
        let now = Date.now
        let hour = Int(now.timeIntervalSince1970) / 3600 * 3600
        let app = "/Applications/HourlyProbe-\(UUID().uuidString).app"
        let silent = "/Applications/Silent-\(UUID().uuidString).app"
        await model.store.add(day: UsageStore.dayKey(now), rows: [], hourly: [
            UsageStore.HourlyRow(hour: hour, app: app, domain: "x.com", mobile: true, bytesIn: 700, bytesOut: 300),
            UsageStore.HourlyRow(hour: hour, app: app, domain: nil, mobile: false, bytesIn: 50, bytesOut: 0),
        ])
        let detail = await model.appDetail(for: app, now: now)
        XCTAssertEqual(detail.hours.count, 1)
        XCTAssertEqual(detail.hours.first?.mobile, 1_000)
        XCTAssertEqual(detail.hours.first?.other, 50)
        XCTAssertEqual(detail.hours.first?.start, Date(timeIntervalSince1970: TimeInterval(hour)))
        XCTAssertEqual(detail.dayStart, cal.startOfDay(for: now))

        // Saatlik kayıt gün ortasında başladıysa, o saatten önceki trafiği olan ama kaydı olmayan uygulama için açıklama.
        let other = await model.appDetail(for: silent, now: now)
        XCTAssertTrue(other.hours.isEmpty)
        let since = try XCTUnwrap(other.hourlySince)
        XCTAssertLessThanOrEqual(since, Date(timeIntervalSince1970: TimeInterval(hour)))
        if since >= other.dayStart {
            XCTAssertTrue(other.hourlyEmptyMessage(hasTraffic: true).contains("itibarıyla"))
        }
        XCTAssertEqual(other.hourlyEmptyMessage(hasTraffic: false), "Bugün için saatlik kayıt yok")
    }
}
