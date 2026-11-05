import XCTest
@testable import Adalmon

final class PanelConfigTests: XCTestCase {
    func testDefaults() {
        let c = PanelConfig()
        XCTAssertEqual(c.density, .compact)
        XCTAssertEqual(c.last60Rows, 3)
        XCTAssertEqual(c.todayRows, 5)
        XCTAssertEqual(c.tileStyle, .compactTiles)
        XCTAssertEqual(c.chartHeight, .small)
        XCTAssertEqual(c.chartHeight.points, 40)
        XCTAssertTrue(c.showTemperatures)
        XCTAssertTrue(c.collapsed.isEmpty)
        XCTAssertEqual(c.visibleSections, [.system, .networkChart, .mobileCap, .blockedApps, .last60, .today])
    }

    func testCodableRoundTrip() throws {
        var c = PanelConfig()
        c.density = .comfortable
        c.tileStyle = .rows
        c.chartHeight = .off
        c.showTemperatures = false
        c.last60Rows = 7
        c.todayRows = 0
        c.collapsed = [.today, .system]
        c.setVisible(.mobileCap, false)
        c.move(.today, by: -1)
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(PanelConfig.self, from: data)
        XCTAssertEqual(decoded, c)
        XCTAssertEqual(decoded.visibleSections, [.system, .networkChart, .blockedApps, .today, .last60])
    }

    func testRowCountClamping() throws {
        XCTAssertEqual(PanelConfig(last60Rows: -4, todayRows: 99).last60Rows, 0)
        XCTAssertEqual(PanelConfig(last60Rows: -4, todayRows: 99).todayRows, 15)
        var c = PanelConfig()
        c.last60Rows = 40
        c.todayRows = -1
        XCTAssertEqual(c.last60Rows, 15)
        XCTAssertEqual(c.todayRows, 0)
        let json = Data(#"{"last60Rows": 100, "todayRows": -3}"#.utf8)
        let decoded = try JSONDecoder().decode(PanelConfig.self, from: json)
        XCTAssertEqual(decoded.last60Rows, 15)
        XCTAssertEqual(decoded.todayRows, 0)
    }

    func testDecodingPartialAndUnknownValuesFallsBackToDefaults() throws {
        let json = Data(#"{"density": "huge", "sections": [{"section": "today", "isVisible": false}, {"section": "today", "isVisible": true}]}"#.utf8)
        let c = try JSONDecoder().decode(PanelConfig.self, from: json)
        XCTAssertEqual(c.density, .compact)
        XCTAssertEqual(c.sections.count, PanelSection.allCases.count)
        XCTAssertEqual(c.sections.first, PanelSectionItem(section: .today, isVisible: false))
        XCTAssertFalse(c.isVisible(.today))
        XCTAssertEqual(c.tileStyle, .compactTiles)
    }

    func testMoveAndCollapse() {
        var c = PanelConfig()
        c.move(.system, by: -1)
        XCTAssertEqual(c.sections.first?.section, .system)
        c.move(.system, by: 1)
        XCTAssertEqual(c.sections.map(\.section).prefix(2), [.networkChart, .system])
        c.toggleCollapsed(.today)
        XCTAssertTrue(c.isCollapsed(.today))
        c.toggleCollapsed(.today)
        XCTAssertFalse(c.isCollapsed(.today))
    }

    @MainActor
    func testStorePersists() throws {
        let suite = "PanelConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PanelConfigStore(defaults: defaults)
        XCTAssertEqual(store.config, PanelConfig())
        store.config.todayRows = 9
        store.config.density = .comfortable
        let reloaded = PanelConfigStore(defaults: defaults)
        XCTAssertEqual(reloaded.config.todayRows, 9)
        XCTAssertEqual(reloaded.config.density, .comfortable)
    }
}
