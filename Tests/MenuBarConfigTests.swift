import XCTest
@testable import Adalmon

final class MenuBarConfigTests: XCTestCase {
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "adalmon.tests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return d
    }

    func testCodableRoundTrip() throws {
        var config = MenuBarPreset.renkli.makeConfig()
        config.displayMode = .separate
        config.spacing = 9
        config.labelOpacity = 0.7
        config.showUnits = false
        config.components[0].customColor = RGBAColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.9)
        config.components[0].thresholds = Thresholds(warning: 0.5, critical: 0.9)
        config.components[1].enabled = false
        config.components[2].colorTarget = .both
        config.components[2].unit = .mb

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MenuBarConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testDecodingFallsBackForMissingFieldsAndInvalidVisual() throws {
        let json = #"{"components":[{"primary":"diskFree","visual":"sparkline"},{"primary":"cpu","secondary":"cpuTemp","visual":"dot"},{"primary":"download"}]}"#
        let decoded = try JSONDecoder().decode(MenuBarConfig.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.components.count, 3)
        XCTAssertTrue(decoded.components.allSatisfy(\.isValid))
        XCTAssertEqual(decoded.components[0].visual, .text, "diskFree has no history")
        XCTAssertEqual(decoded.components[1].visual, .dot)
        XCTAssertNil(decoded.components[1].secondary, "dot has no line 2")
        XCTAssertEqual(decoded.components[2].visual, .text)
        XCTAssertEqual(decoded.displayMode, .combined)
        XCTAssertEqual(decoded.spacing, 6)
        XCTAssertEqual(decoded.labelOpacity, 0.8)
    }

    func testPresetsAreValid() {
        for preset in MenuBarPreset.allCases {
            let components = preset.components
            XCTAssertFalse(components.isEmpty, preset.displayName)
            for c in components { XCTAssertTrue(c.isValid, "\(preset.displayName): \(c.title) / \(c.visual)") }
            XCTAssertTrue(preset.matches(preset.components), "ids must not affect preset matching")
            XCTAssertEqual(MenuBarPreset.matching(preset.components), preset)
        }
        XCTAssertEqual(MenuBarConfig.default.enabledComponents.map(\.primary), [.connection, .cpu, .memoryUsed, .upload])
        XCTAssertEqual(MenuBarConfig.default.displayMode, .combined)
    }

    @MainActor
    func testDefaultsToSimpleCardsWithoutOldFlags() {
        let d = makeDefaults()
        let store = MenuBarConfigStore(defaults: d)
        XCTAssertEqual(store.config, .default)
        XCTAssertNotNil(store.cards, "fresh install uses the simple cards")
        XCTAssertNotNil(d.data(forKey: MenuBarConfigStore.defaultsKey), "migration result is persisted once")
    }

    @MainActor
    func testMigrationFromOldFlagsSeparate() {
        let d = makeDefaults()
        d.set(false, forKey: "showCompactItem")
        d.set(true, forKey: "showCPUItem")
        d.set(true, forKey: "showNetItem")
        let store = MenuBarConfigStore(defaults: d)
        XCTAssertEqual(store.config.displayMode, .separate)
        XCTAssertEqual(store.config.components.map(\.primary), [.cpu, .upload])
        XCTAssertNil(store.currentPreset)
    }

    @MainActor
    func testMigrationKeepsCompactCapsuleWhenItWasOn() {
        let d = makeDefaults()
        d.set(true, forKey: "showRAMItem")
        let store = MenuBarConfigStore(defaults: d)
        XCTAssertEqual(store.config.displayMode, .combined)
        XCTAssertEqual(store.config.components.map(\.primary), [.connection, .cpu, .memoryPercent, .upload, .memoryPercent])
    }

    @MainActor
    func testMigrationRunsOnlyOnceAndChangesPersist() {
        let d = makeDefaults()
        let store = MenuBarConfigStore(defaults: d)
        store.apply(.grafik)
        store.config.spacing = 3
        d.set(true, forKey: "showGPUItem")
        let reloaded = MenuBarConfigStore(defaults: d)
        XCTAssertEqual(reloaded.currentPreset, .grafik)
        XCTAssertEqual(reloaded.config.spacing, 3)
    }

    @MainActor
    func testEditingAddingMovingAndReset() {
        let store = MenuBarConfigStore(defaults: makeDefaults())
        store.config.components[1].visual = .ring
        XCTAssertNil(store.currentPreset)
        store.move(id: store.config.components[0].id, by: 1)
        XCTAssertEqual(store.config.components[1].primary, .connection)

        let entry = ComponentLibrary.entries[1]
        let id = store.add(entry.component)
        XCTAssertNotEqual(id, entry.component.id, "library adds get a fresh id")
        XCTAssertEqual(store.config.components.last?.id, id)
        store.move(id: id, onto: store.config.components[0].id)
        XCTAssertEqual(store.config.components.first?.id, id)
        store.remove(id: id)
        XCTAssertFalse(store.config.components.contains { $0.id == id })

        store.config.spacing = 9
        store.resetToDefault()
        XCTAssertEqual(store.config.components, MenuBarConfig.default.components)
        XCTAssertEqual(store.config.spacing, 6)
    }

    func testThresholdColorSelection() {
        let t = Thresholds()
        XCTAssertEqual(t.level(for: 0.599), .normal)
        XCTAssertEqual(t.level(for: 0.6), .warning)
        XCTAssertEqual(t.level(for: 0.8), .critical)

        var c = MenuBarComponent(.cpu, visual: .ring, colorMode: .threshold)
        XCTAssertEqual(WidgetPalette.graphic(for: c, field: .cpu, level: 0.46, connection: .online), .systemGreen)
        XCTAssertEqual(WidgetPalette.graphic(for: c, field: .cpu, level: 0.7, connection: .online), .systemOrange)
        XCTAssertEqual(WidgetPalette.graphic(for: c, field: .cpu, level: 0.9, connection: .online), .systemRed)
        XCTAssertEqual(WidgetPalette.valueText(for: c, field: .cpu, level: 0.9, connection: .online), .labelColor,
                       "target .visual leaves ring value text neutral")
        c.colorTarget = .value
        XCTAssertEqual(WidgetPalette.graphic(for: c, field: .cpu, level: 0.9, connection: .online), .labelColor)
        XCTAssertEqual(WidgetPalette.valueText(for: c, field: .cpu, level: 0.9, connection: .online), .systemRed)
        let text = MenuBarComponent(.cpu, colorMode: .threshold)
        XCTAssertEqual(WidgetPalette.valueText(for: text, field: .cpu, level: 0.9, connection: .online), .systemRed,
                       "text-only visuals color their value")
    }

    func testGradientAndMinimumAlpha() {
        let start = RGBAColor(red: 0, green: 1, blue: 0)
        let end = RGBAColor(red: 1, green: 0, blue: 0.5, alpha: 0.8)
        XCTAssertEqual(start.interpolated(to: end, fraction: 2), end)
        let c = MenuBarComponent(.memoryPercent, visual: .ring, colorMode: .gradient, gradientStart: start, gradientEnd: end)
        XCTAssertEqual(WidgetPalette.fixedColor(for: c, level: 0), start)
        XCTAssertEqual(WidgetPalette.fixedColor(for: c, level: 1), end)
        let faint = MenuBarComponent(.cpu, colorMode: .custom, customColor: RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.2))
        XCTAssertGreaterThanOrEqual(WidgetPalette.valueText(for: faint, field: .cpu, level: 0.5, connection: .online).alphaComponent,
                                    WidgetPalette.minimumTextAlpha)
        XCTAssertGreaterThanOrEqual(WidgetPalette.label(opacity: 0.1).alphaComponent, 0.6)
    }

    func testHexColor() {
        XCTAssertEqual(RGBAColor(hex: "#FF0000"), RGBAColor(red: 1, green: 0, blue: 0))
        XCTAssertNil(RGBAColor(hex: "zz"))
    }

    func testAccessibilitySummary() {
        let summary = MenuBarComposer.accessibilitySummary(for: MenuBarPreset.kompakt.components, values: .sample)
        XCTAssertTrue(summary.contains("CPU kullanımı %46"), summary)
        XCTAssertTrue(summary.contains("Bellek (%) %78"), summary)
        XCTAssertTrue(summary.contains("İndirme hızı 18,4 MB/s"), summary)
        XCTAssertTrue(summary.contains("Bağlantı Wi-Fi"), summary)
    }

    func testRenderKeyTracksSecondLine() {
        let c = [MenuBarComponent(.cpu, .cpuTemp, visual: .stacked2)]
        let config = MenuBarConfig(components: c)
        var hot = WidgetValues.sample
        hot.temperature?.cpu = 91
        XCTAssertNotEqual(MenuBarRenderKey(components: c, config: config, values: .sample),
                          MenuBarRenderKey(components: c, config: config, values: hot))
        let chart = [MenuBarComponent(.download, .upload, visual: .sparkline, showValue: false)]
        var other = WidgetValues.sample
        other.upHistory = other.upHistory.reversed()
        XCTAssertNotEqual(MenuBarRenderKey(components: chart, config: config, values: .sample),
                          MenuBarRenderKey(components: chart, config: config, values: other))
    }

    func testComposerFramesMatchWidths() {
        let config = MenuBarPreset.ayrintili.makeConfig()
        let frames = MenuBarComposer.frames(of: config.components, config: config, values: .sample)
        XCTAssertEqual(frames.count, config.components.count)
        XCTAssertEqual(frames.last.map { $0.upperBound + MenuBarComposer.horizontalPadding } ?? 0,
                       MenuBarComposer.width(of: config.components, config: config, values: .sample), accuracy: 0.001)
    }
}
