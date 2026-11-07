import XCTest
@testable import Adalmon

final class PanelConfigTests: XCTestCase {
    func testDefaults() {
        let c = PanelConfig()
        XCTAssertEqual(c.density, .compact)
        XCTAssertEqual(c.last60Rows, 3)
        XCTAssertEqual(c.todayRows, 5)
        XCTAssertTrue(c.collapsed.isEmpty)
        XCTAssertEqual(c.visibleSections, [.system, .battery, .mobileCap, .blockedApps, .last60, .today])
        XCTAssertEqual(c.visibleCards, [.cpu, .gpu, .memory, .temperature, .download, .upload])
        XCTAssertEqual(c.cards.map(\.kind), [.cpu, .gpu, .memory, .temperature, .download, .upload, .disk])
        XCTAssertFalse(c.isVisible(PanelCardKind.disk))
    }

    func testCodableRoundTrip() throws {
        var c = PanelConfig()
        c.density = .comfortable
        c.setVisible(.disk, true)
        c.setVisible(.gpu, false)
        c.move(.upload, by: -1)
        c.last60Rows = 7
        c.todayRows = 0
        c.collapsed = [.today, .system]
        c.setVisible(.mobileCap, false)
        c.move(.today, by: -1)
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(PanelConfig.self, from: data)
        XCTAssertEqual(decoded, c)
        XCTAssertEqual(decoded.visibleSections, [.system, .battery, .blockedApps, .today, .last60])
        XCTAssertEqual(decoded.visibleCards, [.cpu, .memory, .temperature, .upload, .download, .disk])
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
        XCTAssertEqual(c.visibleCards.count, 6)
    }

    /// Eski sürümden kalan kayıt: kaldırılan "networkChart" bölümü ve eski anahtarlar yüzünden sıra sıfırlanmamalı.
    func testLegacyStoredConfigKeepsOrderAndDropsUnknownSection() throws {
        let json = Data(#"""
        {"sections": [{"section":"today","isVisible":true},{"section":"networkChart","isVisible":true},{"section":"system","isVisible":false}],
         "collapsed": ["networkChart","today"], "tileStyle": "cards", "chartHeight": "off", "showTemperatures": false}
        """#.utf8)
        let c = try JSONDecoder().decode(PanelConfig.self, from: json)
        XCTAssertEqual(c.sections.map(\.section).prefix(2), [.today, .system])
        XCTAssertFalse(c.isVisible(.system))
        XCTAssertEqual(c.sections.count, PanelSection.allCases.count)
        XCTAssertEqual(c.collapsed, [.today])
        XCTAssertEqual(c.cards, PanelConfig.defaultCards)
    }

    func testCardsNormalizeAndMove() {
        var c = PanelConfig(cards: [PanelCardItem(kind: .upload, isVisible: true), PanelCardItem(kind: .upload, isVisible: false)])
        XCTAssertEqual(c.cards.count, PanelCardKind.allCases.count)
        XCTAssertEqual(c.cards.first, PanelCardItem(kind: .upload, isVisible: true))
        c.move(.upload, by: -1)
        XCTAssertEqual(c.cards.first?.kind, .upload)
        c.move(.upload, by: 1)
        XCTAssertEqual(c.cards[1].kind, .upload)
    }

    func testMoveAndCollapse() {
        var c = PanelConfig()
        c.move(.system, by: -1)
        XCTAssertEqual(c.sections.first?.section, .system)
        c.move(.system, by: 1)
        XCTAssertEqual(c.sections.map(\.section).prefix(2), [.battery, .system])
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
