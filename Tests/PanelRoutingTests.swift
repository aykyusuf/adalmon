import XCTest
@testable import Adalmon

/// Menü çubuğu öğesi → panel türü, öğe başına geçersiz kılma, "Tıklayınca" ayarı ve aç/kapat/değiştir mantığı.
@MainActor
final class PanelRoutingTests: XCTestCase {
    func testPrimaryFieldCategoryDecidesPanel() {
        let cases: [(DataField, PanelKind)] = [
            (.cpu, .cpu), (.cpuTemp, .temperature), (.gpu, .gpu), (.gpuTemp, .temperature), (.memoryPercent, .memory),
            (.memoryFree, .memory), (.diskFree, .disk), (.diskRead, .disk), (.download, .network), (.uploadToday, .network),
            (.mobilePercent, .network), (.connection, .network), (.batteryLevel, .battery), (.ssdTemp, .temperature),
        ]
        for (field, expected) in cases {
            XCTAssertEqual(PanelRouter.kind(for: [MenuBarComponent(field)], clickMode: .perMetric), expected, "\(field)")
        }
    }

    func testItemCombiningMetricsUsesFirstComponent() {
        let combined = MenuBarComponent(.cpu, .memoryPercent, visual: .stacked2)
        XCTAssertEqual(PanelRouter.kind(for: [combined], clickMode: .perMetric), .cpu)
        // Birden çok bileşenli grupta ilki birincildir.
        XCTAssertEqual(PanelRouter.kind(for: [MenuBarComponent(.diskFree), MenuBarComponent(.cpu)], clickMode: .perMetric), .disk)
    }

    func testBatteryCapsuleAndPinnedDeviceOpenBatteryPanel() {
        XCTAssertEqual(PanelRouter.kind(for: [MenuBarComponent(.batteryLevel, visual: .batteryCapsule)], clickMode: .perMetric), .battery)
        XCTAssertEqual(PanelRouter.kind(for: [.device("airpods-1", name: "AirPods")], clickMode: .perMetric), .battery)
    }

    func testPerItemOverrideWinsAndCombinedModeIgnoresIt() {
        var c = MenuBarComponent(.cpu)
        c.panelKind = .temperature
        XCTAssertEqual(PanelRouter.kind(for: [c], clickMode: .perMetric), .temperature)
        c.panelKind = .combined
        XCTAssertEqual(PanelRouter.kind(for: [c], clickMode: .perMetric), .combined)
        c.panelKind = .gpu
        XCTAssertEqual(PanelRouter.kind(for: [c], clickMode: .combined), .combined, "Birleşik mod her şeyi birleşik panele yönlendirir")
        XCTAssertEqual(PanelRouter.kind(for: [], clickMode: .perMetric), .combined, "boş öğe (yer tutucu) birleşik panel açar")
    }

    func testHitTestingPicksComponentUnderClick() {
        let comps = [MenuBarComponent(.cpu), MenuBarComponent(.download), MenuBarComponent(.diskFree)]
        let frames: [ClosedRange<CGFloat>] = [1...41, 47...100, 106...150]
        XCTAssertEqual(PanelRouter.component(at: 20, in: comps, frames: frames)?.primary, .cpu)
        XCTAssertEqual(PanelRouter.component(at: 60, in: comps, frames: frames)?.primary, .download)
        XCTAssertEqual(PanelRouter.component(at: 104, in: comps, frames: frames)?.primary, .diskFree, "boşluk: en yakın bileşen")
        XCTAssertNil(PanelRouter.component(at: 5, in: [], frames: []))
    }

    func testToggleLogic() {
        let a = PanelRoute(itemKey: "item.A", kind: .cpu)
        let b = PanelRoute(itemKey: "item.B", kind: .gpu)
        let aOther = PanelRoute(itemKey: "item.A", kind: .memory)
        let bSameKind = PanelRoute(itemKey: "item.B", kind: .cpu)
        XCTAssertEqual(PanelToggle.next(current: nil, click: a), .open)
        XCTAssertEqual(PanelToggle.next(current: a, click: a), .close, "aynı öğeye tekrar tıklamak kapatır")
        XCTAssertEqual(PanelToggle.next(current: a, click: b), .switchTo)
        XCTAssertEqual(PanelToggle.next(current: a, click: bSameKind), .switchTo, "aynı tür başka öğe: yeniden konumlan")
        XCTAssertEqual(PanelToggle.next(current: a, click: aOther), .switchTo, "birleşik öğede başka bileşen")
    }

    func testLiveSamplingOnlyForRelevantKinds() {
        XCTAssertEqual(PanelKind.allCases.filter(\.needsBatterySampling).sorted { $0.rawValue < $1.rawValue }, [.battery, .combined])
        XCTAssertEqual(Set(PanelKind.allCases.filter(\.needsLiveProcesses)), [.cpu, .gpu, .memory])
    }

    // MARK: Ayar kalıcılığı

    func testClickModeAndOverrideRoundTrip() throws {
        var config = MenuBarConfig.default
        config.clickMode = .combined
        config.components[0].panelKind = .temperature
        let decoded = try JSONDecoder().decode(MenuBarConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.clickMode, .combined)
        XCTAssertEqual(decoded.components[0].panelKind, .temperature)
        XCTAssertEqual(decoded, config)
    }

    func testLegacyConfigWithoutKeysDefaultsToPerMetric() throws {
        let data = try JSONEncoder().encode(MenuBarConfig.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "clickMode")
        let decoded = try JSONDecoder().decode(MenuBarConfig.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.clickMode, .perMetric)
        XCTAssertNil(decoded.components.first?.panelKind)
        // Bozuk değer varsayılana düşer.
        object["clickMode"] = "nonsense"
        XCTAssertEqual(try JSONDecoder().decode(MenuBarConfig.self, from: JSONSerialization.data(withJSONObject: object)).clickMode, .perMetric)
    }

    func testOverrideDoesNotBreakPresetOrCardMatching() {
        var c = MenuBarComponent(.cpu)
        let plain = c
        c.panelKind = .gpu
        XCTAssertTrue(c.isEquivalent(to: plain))
        XCTAssertNotEqual(c, plain)
    }

    func testDetailCollapsedIsRememberedAndTolerant() throws {
        var config = PanelConfig()
        config.toggleDetailCollapsed("battery.info")
        XCTAssertTrue(config.isDetailCollapsed("battery.info"))
        let decoded = try JSONDecoder().decode(PanelConfig.self, from: JSONEncoder().encode(config))
        XCTAssertTrue(decoded.isDetailCollapsed("battery.info"))
        XCTAssertEqual(decoded.sections.count, PanelSection.allCases.count, "yeni kimlikler birleşik paneli etkilemez")
        let legacy = try JSONDecoder().decode(PanelConfig.self, from: Data(#"{"density":"compact"}"#.utf8))
        XCTAssertTrue(legacy.detailCollapsed.isEmpty)
    }
}
