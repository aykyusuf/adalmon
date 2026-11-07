import XCTest
@testable import Adalmon

/// Faz 6: iskelet durumu, panel zemini kalıcılığı, cihaz sabitleme → ayrı durum öğesi eşlemesi, kart varsayılanları.
@MainActor
final class PanelSkeletonTests: XCTestCase {
    // MARK: İskelet durumu

    func testListLoadStateResolution() {
        XCTAssertEqual(ListLoadState.resolve(isLoading: true, itemCount: 0), .loading)
        XCTAssertEqual(ListLoadState.resolve(isLoading: false, itemCount: 0), .empty)
        XCTAssertEqual(ListLoadState.resolve(isLoading: true, itemCount: 3), .loaded, "veri gelince iskelet biter")
        XCTAssertEqual(ListLoadState.resolve(isLoading: false, itemCount: 3), .loaded)
        XCTAssertEqual(ListLoadState.resolve(isLoading: true, itemCount: 0, timedOut: true), .empty, "iskelet sonsuza dek kalmaz")
        XCTAssertGreaterThan(ListLoadState.timeout, 1)
    }

    func testPanelLiveSourcesStartInMeasuringStateAndFinishWithFixtures() {
        let live = PanelLiveSources(model: nil)
        XCTAssertTrue(live.isMeasuring, "ilk veri gelene kadar iskelet")
        XCTAssertTrue(live.processes.isEmpty)
        live.setFixtures(processes: PanelData.metricProcesses)
        XCTAssertFalse(live.isMeasuring)
        XCTAssertEqual(ListLoadState.resolve(isLoading: live.isMeasuring, itemCount: live.processes.count), .loaded)
    }

    func testFirstDeltaIsFasterThanOneInterval() {
        XCTAssertLessThanOrEqual(PanelLiveSources.firstDeltaDelay, .milliseconds(600))
    }

    func testPlaceholderRowsAreStableAndNeverEmpty() {
        for i in 0..<8 {
            let p = TopProcess.placeholder(i)
            XCTAssertFalse(p.name.isEmpty)
            XCTAssertFalse(p.valueText.isEmpty)
        }
        XCTAssertEqual(Set((0..<5).map { TopProcess.placeholder($0).id }).count, 5)
    }

    // MARK: Panel zemini

    private func suite() throws -> UserDefaults { try XCTUnwrap(UserDefaults(suiteName: "adalmon.p6.\(UUID().uuidString)")) }

    func testBackgroundDefaultsToSolid() {
        XCTAssertEqual(PanelConfig().background, .solid)
        XCTAssertEqual(PanelBackground.solid.displayName, "Koyu (opak)")
        XCTAssertEqual(PanelBackground.glass.displayName, "Cam (saydam)")
    }

    func testBackgroundPersistsThroughStore() throws {
        let defaults = try suite()
        let store = PanelConfigStore(defaults: defaults)
        XCTAssertEqual(store.config.background, .solid)
        store.config.background = .glass
        let reloaded = PanelConfigStore(defaults: defaults)
        XCTAssertEqual(reloaded.config.background, .glass)
        reloaded.reset()
        XCTAssertEqual(PanelConfigStore(defaults: defaults).config.background, .solid)
    }

    func testLegacyConfigWithoutBackgroundDecodesAsSolid() throws {
        let legacy = Data(#"{"density":"compact","last60Rows":3,"todayRows":5,"detailCollapsed":["battery.devices"]}"#.utf8)
        let config = try JSONDecoder().decode(PanelConfig.self, from: legacy)
        XCTAssertEqual(config.background, .solid)
        XCTAssertTrue(config.isDetailCollapsed("battery.devices"))
        let unknown = Data(#"{"background":"neon"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(PanelConfig.self, from: unknown).background, .solid, "bilinmeyen değer varsayılana düşer")
    }

    func testDefaultCollapsedSectionTogglesAndIsRemembered() throws {
        var config = PanelConfig()
        XCTAssertTrue(config.isDetailCollapsed("battery.info", defaultCollapsed: true), "Pil bilgisi kapalı başlar")
        XCTAssertFalse(config.isDetailCollapsed("battery.apps"), "diğerleri açık başlar")
        config.toggleDetailCollapsed("battery.info", defaultCollapsed: true)
        XCTAssertFalse(config.isDetailCollapsed("battery.info", defaultCollapsed: true))
        let defaults = try suite()
        let store = PanelConfigStore(defaults: defaults)
        store.config = config
        XCTAssertFalse(PanelConfigStore(defaults: defaults).config.isDetailCollapsed("battery.info", defaultCollapsed: true), "durum hatırlanır")
        config.toggleDetailCollapsed("battery.info", defaultCollapsed: true)
        XCTAssertTrue(config.isDetailCollapsed("battery.info", defaultCollapsed: true))
        config.toggleDetailCollapsed("battery.apps")
        XCTAssertTrue(config.isDetailCollapsed("battery.apps"))
        config.toggleDetailCollapsed("battery.apps")
        XCTAssertFalse(config.isDetailCollapsed("battery.apps"))
    }

    // MARK: Cihaz sabitleme → ayrı durum öğesi

    private func config(pinned: [String], mode: MenuBarDisplayMode) -> MenuBarConfig {
        var c = MenuBarConfig.default
        c.displayMode = mode
        c.components += pinned.map { MenuBarComponent.device($0, name: $0) }
        return c
    }

    func testPinnedDeviceGetsItsOwnItemInCombinedMode() {
        let groups = StatusItemPlan.groups(for: config(pinned: ["yusuf iphone"], mode: .combined))
        let combined = groups.first { $0.key == StatusItemPlan.combinedKey }
        XCTAssertNotNil(combined)
        XCTAssertTrue(combined?.items.allSatisfy { $0.deviceID == nil } ?? false, "cihaz birleşik öğeye karışmamalı")
        let device = groups.filter { $0.items.contains { $0.deviceID != nil } }
        XCTAssertEqual(device.count, 1)
        XCTAssertEqual(device.first?.items.count, 1, "tek başına öğe")
        XCTAssertEqual(device.first?.key, StatusItemPlan.deviceKey("yusuf iphone"))
    }

    func testPinnedDevicesAreSeparateInSeparateModeToo() {
        let c = config(pinned: ["a", "b"], mode: .separate)
        let groups = StatusItemPlan.groups(for: c)
        XCTAssertEqual(groups.count, c.enabledComponents.count, "her bileşen kendi öğesi")
        XCTAssertEqual(Set(groups.map(\.key)).count, groups.count, "anahtarlar benzersiz")
        XCTAssertTrue(groups.allSatisfy { $0.items.count == 1 })
    }

    func testUnpinRemovesItsItemAndKeepsOthers() throws {
        let store = MenuBarConfigStore(defaults: try suite())
        let before = StatusItemPlan.groups(for: store.config).map(\.key)
        store.setPinned(device: "yusuf iphone", name: "Yusuf iPhone", true)
        let pinned = StatusItemPlan.groups(for: store.config).map(\.key)
        XCTAssertEqual(pinned.count, before.count + 1)
        XCTAssertTrue(pinned.contains(StatusItemPlan.deviceKey("yusuf iphone")))
        store.setPinned(device: "yusuf iphone", false)
        XCTAssertEqual(StatusItemPlan.groups(for: store.config).map(\.key), before)
    }

    func testDeviceKeyIsStableAndSafe() {
        XCTAssertEqual(StatusItemPlan.deviceKey("yusuf's airpods pro"), "device.yusuf-s-airpods-pro")
        XCTAssertEqual(StatusItemPlan.deviceKey("yusuf's airpods pro"), StatusItemPlan.deviceKey("yusuf's airpods pro"))
    }

    func testOnlyDeviceItemsDoNotCreatePlaceholder() {
        var c = MenuBarConfig(components: [.device("a")])
        XCTAssertEqual(StatusItemPlan.groups(for: c).map(\.key), [StatusItemPlan.deviceKey("a")])
        c.components = []
        XCTAssertEqual(StatusItemPlan.groups(for: c), [StatusItemPlan.Group(key: StatusItemPlan.combinedKey, items: [])], "boşken tıklanabilir yer tutucu")
    }

    func testDuplicatePinsGetDistinctKeys() {
        let c = MenuBarConfig(components: [.device("a"), .device("a")])
        let keys = StatusItemPlan.groups(for: c).map(\.key)
        XCTAssertEqual(Set(keys).count, 2)
    }

    func testDeviceItemClickOpensBatteryPanelFocusedOnDevice() {
        let device = MenuBarComponent.device("airpods-1", name: "AirPods")
        XCTAssertEqual(PanelRouter.kind(for: [device], clickMode: .combined), .battery, "cihaz öğesi birleşik modda da Pil panelini açar")
        XCTAssertEqual(PanelRouter.focusDeviceID(for: [device]), "airpods-1")
        XCTAssertNil(PanelRouter.focusDeviceID(for: [MenuBarComponent(.cpu)]))
        let a = PanelRoute(itemKey: "device.x", kind: .battery, focusDeviceID: "x")
        XCTAssertEqual(PanelToggle.next(current: a, click: a), .close)
        XCTAssertEqual(PanelToggle.next(current: a, click: PanelRoute(itemKey: "device.y", kind: .battery, focusDeviceID: "y")), .switchTo)
    }

    // MARK: Cihaz görünümü

    func testDeviceItemShowsPercentSuffixAndLowLevelColor() {
        var state = BatteryGlyphState(device: DeviceBattery(id: "a", name: "A", kind: .iPhone, level: 32, lastSeen: .now))
        XCTAssertEqual(BatteryGlyph.deviceText(state), "32%")
        let c = MenuBarComponent.device("a")
        XCTAssertNil(BatteryGlyph.deviceTint(c, state))
        state.level = 15
        XCTAssertEqual(BatteryGlyph.deviceTint(c, state), .systemOrange)
        state.level = 8
        XCTAssertEqual(BatteryGlyph.deviceTint(c, state), .systemRed)
        state.isCharging = true
        XCTAssertNil(BatteryGlyph.deviceTint(c, state), "şarjda renk değil şimşek")
        XCTAssertEqual(BatteryGlyph.deviceText(nil), "–%")
    }

    func testDevicePanelTintFollowsLevelRules() {
        func d(_ level: Int, charging: Bool = false) -> DeviceBattery {
            DeviceBattery(id: "a", name: "A", kind: .iPhone, level: level, isCharging: charging, lastSeen: .now)
        }
        XCTAssertEqual(DevicePalette.panelTint(d(18)), .orange)
        XCTAssertEqual(DevicePalette.panelTint(d(95)), .green)
        XCTAssertEqual(DevicePalette.panelTint(d(40, charging: true)), .green)
        XCTAssertEqual(DevicePalette.panelTint(d(5)), .red)
        XCTAssertEqual(d(32).percentText, "32%")
    }

    // MARK: Pil kartı (Ayarlar › Menü çubuğu)

    func testBatteryCardAddsMacCapsule() throws {
        let store = MenuBarConfigStore(defaults: try suite())
        var cards = try XCTUnwrap(store.cards)
        let index = try XCTUnwrap(cards.firstIndex { $0.kind == .battery })
        XCTAssertFalse(cards[index].shown, "varsayılan gizli")
        cards[index].shown = true
        cards[index].showTime = true
        store.apply(cards: cards)
        let capsule = try XCTUnwrap(store.config.enabledComponents.first { $0.visual == .batteryCapsule && $0.deviceID == nil })
        XCTAssertTrue(capsule.battery.showTime)
        XCTAssertEqual(try XCTUnwrap(store.cards)[index].showTime, true, "karta geri okunur")
    }
}
