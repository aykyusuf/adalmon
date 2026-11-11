import XCTest
@testable import Adalmon

final class MetricCardConfigTests: XCTestCase {
    private let v = WidgetValues.sample

    private func cpuCard(_ layout: MetricLayout) -> MetricCardConfig {
        MetricCardConfig(.cpu, shown: true, fields: [.cpu, .cpuTemp], layout: layout)
    }

    private func width(_ card: MetricCardConfig, _ values: WidgetValues? = nil, config: MenuBarConfig = .default) -> CGFloat {
        MenuBarComposer.widths(of: card.components(), config: config, values: values ?? v).reduce(0, +)
    }

    // MARK: Mapping

    func testCardMapsToOneComponent() throws {
        let c = try XCTUnwrap(cpuCard(.inline).components().first)
        XCTAssertEqual(cpuCard(.inline).components().count, 1)
        XCTAssertEqual(c.fields, [.cpu, .cpuTemp])
        XCTAssertEqual(c.visual, .oneLine)
        XCTAssertEqual(c.layout, .inline)
        XCTAssertTrue(c.isValid)

        var memory = MetricCardConfig(.memory, shown: true, fields: [.memoryUsed, .memoryFree, .memoryPercent], layout: .labelAbove)
        XCTAssertEqual(memory.components().first?.fields, [.memoryUsed, .memoryFree, .memoryPercent], "three values in one component")
        memory.thresholdColor = true
        XCTAssertEqual(memory.components().first?.colorMode, .threshold)
        XCTAssertEqual(memory.components().first?.colorTarget, .value)

        var cpu = cpuCard(.symbol)
        cpu.showGraph = true
        XCTAssertEqual(cpu.components().map(\.visual), [.symbolStack, .sparkline], "Grafik adds a line chart after the values")

        var net = MetricCardConfig(.network, shown: true, fields: [.download, .upload], layout: .symbol, networkSource: .today)
        XCTAssertEqual(net.components().first?.fields, [.uploadToday, .downloadToday])
        net.shown = false
        XCTAssertEqual(net.components().first?.enabled, false, "hidden cards keep their component, disabled")

        XCTAssertEqual(MetricCardConfig(.connection, shown: true, fields: [], showLabel: false).components().map(\.visual), [.dot])
    }

    func testCardRoundTripIsExhaustive() {
        var cards: [MetricCardConfig] = []
        for kind in MetricCardKind.allCases {
            let options = kind.options
            let subsets = (0..<(1 << options.count)).map { mask in options.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element) }
            for fields in subsets {
                for graph in kind.graphField == nil ? [false] : [false, true] where !fields.isEmpty || graph || kind == .connection {
                    for layout in kind.hasLayout ? MetricLayout.allCases : [.inline] {
                        for flags in 0..<8 {
                            let sources = kind == .network ? NetworkCardSource.allCases : [.speed]
                            for source in sources {
                                var card = MetricCardConfig(kind, shown: flags & 1 != 0, fields: fields, showGraph: graph, layout: layout,
                                                            thresholdColor: flags & 2 != 0, showLabel: flags & 4 != 0, networkSource: source)
                                if kind == .connection { card.fields = [] }
                                cards.append(card)
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(cards.count, 500)
        var failures = 0
        for card in cards {
            let parsed = MetricCardConfig.cards(from: card.components())
            if parsed?.first != card { failures += 1 }
        }
        XCTAssertEqual(failures, 0, "card -> components -> card must be the identity")
    }

    func testOrderAndHiddenCardsSurvive() throws {
        var cards = MetricCardConfig.defaults
        cards.swapAt(1, 3)
        cards[2].shown = false
        let parsed = try XCTUnwrap(MetricCardConfig.cards(from: MetricCardConfig.components(for: cards)))
        XCTAssertEqual(parsed, cards)
        XCTAssertEqual(MetricCardConfig.cards(from: [])?.count, MetricCardKind.allCases.count, "missing cards appended hidden")
        XCTAssertTrue(MetricCardConfig.cards(from: [])?.allSatisfy { !$0.shown } ?? false)
    }

    func testLastValueCannotBeRemoved() {
        var card = MetricCardConfig(.memory, shown: true, fields: [.memoryUsed])
        XCTAssertFalse(card.canDeselect(.memoryUsed))
        card.set(.memoryUsed, selected: false)
        XCTAssertEqual(card.fields, [.memoryUsed])
        card.set(.memoryPercent, selected: true)
        card.set(.memoryFree, selected: true)
        XCTAssertEqual(card.fields, [.memoryUsed, .memoryFree, .memoryPercent], "kept in option order")
    }

    // MARK: Default config and advanced notice

    func testDefaultConfigIsSimpleCards() throws {
        let cards = try XCTUnwrap(MetricCardConfig.cards(from: MenuBarConfig.default.components))
        XCTAssertEqual(cards, MetricCardConfig.defaults)
        let shown = MenuBarConfig.default.enabledComponents
        XCTAssertEqual(shown.map(\.fields), [[.connection], [.cpu, .cpuTemp], [.memoryUsed], [.upload, .download]])
        XCTAssertEqual(shown.map(\.visual), [.dot, .oneLine, .oneLine, .symbolStack])
        XCTAssertEqual(MenuBarConfig.default.displayMode, .combined)
    }

    @MainActor
    func testAdvancedConfigNoticeDetection() throws {
        let suite = "MetricCardConfigTests-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let store = MenuBarConfigStore(defaults: d)
        XCTAssertNotNil(store.cards, "fresh install is representable by cards")

        store.apply(.ayrintili)
        XCTAssertNil(store.cards, "presets from the advanced editor show the notice")
        store.resetToSimpleLayout()
        XCTAssertEqual(store.cards, MetricCardConfig.defaults)

        store.config.components[1].colorMode = .gradient
        XCTAssertNil(store.cards, "an advanced-only option (gradient) can't be shown as a card")
        store.resetToSimpleLayout()
        store.add(ComponentLibrary.entries[0].component)
        XCTAssertNil(store.cards, "a library component has no card")

        var legacy = MenuBarPreset.kompakt.makeConfig()
        legacy.spacing = 4
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(MenuBarConfig.self, from: data)
        XCTAssertNil(MetricCardConfig.cards(from: decoded.components), "older saved configs still load, as advanced")
        XCTAssertEqual(decoded.components.count, 4)

        var simple = MenuBarConfig.default
        simple.components[1].enabled = false
        let roundTrip = try JSONDecoder().decode(MenuBarConfig.self, from: JSONEncoder().encode(simple))
        XCTAssertEqual(roundTrip, simple, "layout and tertiary persist")
        XCTAssertEqual(MetricCardConfig.cards(from: roundTrip.components)?[1].shown, false)
    }

    // MARK: Widths

    func testCompactWidthsMeetTargets() {
        let inline = width(cpuCard(.inline)), above = width(cpuCard(.labelAbove)), symbol = width(cpuCard(.symbol))
        let ram = MetricLayout.allCases.map { width(MetricCardConfig(.memory, shown: true, fields: [.memoryUsed], layout: $0)) }
        let net = MetricLayout.allCases.map { width(MetricCardConfig(.network, shown: true, fields: [.download, .upload], layout: $0)) }
        print("MENUBAR_WIDTH cpu%+° inline=\(inline) labelAbove=\(above) symbol=\(symbol)")
        print("MENUBAR_WIDTH ram-used inline/labelAbove/symbol=\(ram)")
        print("MENUBAR_WIDTH net↓↑ inline/labelAbove/symbol=\(net)")
        print("MENUBAR_WIDTH default total=\(MenuBarComposer.width(of: MenuBarConfig.default.enabledComponents, config: .default, values: v))")
        XCTAssertLessThanOrEqual(inline, 72)
        XCTAssertLessThanOrEqual(above, 56)
        XCTAssertLessThanOrEqual(symbol, 44)
    }

    func testCompactWidthsAreStable() {
        var low = v
        low.cpu = 0
        low.temperature = nil
        low.memUsed = 0
        low.down = 0
        low.up = 0
        var high = v
        high.cpu = 1
        high.memUsed = high.memTotal
        high.down = 99_000_000
        high.up = 950_000
        high.temperature = TemperatureStats(cpu: 104, cpuMax: 108, gpu: 99, ssd: 70, battery: 45)
        high.mobileUsed = 2_950_000_000
        high.diskFree = high.diskTotal - 1
        for layout in MetricLayout.allCases {
            for kind in MetricCardKind.allCases where kind.hasLayout {
                var card = MetricCardConfig.defaultCard(kind)
                card.fields = kind.options
                card.layout = layout
                card.showGraph = kind.graphField != nil
                for units in [true, false] {
                    var config = MenuBarConfig.default
                    config.showUnits = units
                    let widths = [v, low, high].map { width(card, $0, config: config) }
                    XCTAssertEqual(Set(widths).count, 1, "\(kind) \(layout) units:\(units): \(widths)")
                }
            }
        }
    }

    func testCompactTexts() {
        XCTAssertEqual(DataField.cpuTemp.compactText(v, showUnits: true, unit: .auto), "54°")
        XCTAssertEqual(DataField.cpuTemp.compactText(v, showUnits: true, unit: .auto, bareTemperature: true), "54")
        XCTAssertEqual(DataField.cpu.compactText(v, showUnits: true, unit: .auto), "%46")
        XCTAssertEqual(DataField.memoryUsed.compactText(v, showUnits: true, unit: .gb), "12,5GB")
        XCTAssertEqual(DataField.cpuTemp.columnLabel(isFirst: false), "°C")
    }

    // MARK: Seviye renkleri ve eşikler (MEM-COLOR-01)

    func testCardColorsAndThresholdsRoundTrip() throws {
        var memory = MetricCardConfig(.memory, shown: true, fields: [.memoryFree], layout: .labelAbove, thresholdColor: true)
        memory.levelColors = ThresholdColors(normal: .none, warning: .custom(.blue), critical: .automatic)
        memory.effectiveThresholds = Thresholds(warning: 0.45, critical: 0.9)
        var cpu = MetricCardConfig(.cpu, shown: true, fields: [.cpu, .cpuTemp], showGraph: true)
        cpu.levelColors.normal = .none
        cpu.effectiveThresholds = Thresholds(warning: 0.3, critical: 0.5)
        var cards = MetricCardConfig.defaults
        cards[1] = cpu
        cards[2] = memory

        let components = MetricCardConfig.components(for: cards)
        let mem = try XCTUnwrap(components.first { $0.primary == .memoryFree })
        XCTAssertEqual(mem.levelColors, memory.levelColors)
        XCTAssertEqual(mem.thresholds, Thresholds(warning: 0.45, critical: 0.9))
        XCTAssertEqual(components.first { $0.primary == .cpu && $0.visual == .sparkline }?.thresholds,
                       Thresholds(warning: 0.3, critical: 0.5), "aynı ölçekteki grafik de özel eşikleri kullanır")

        let parsed = try XCTUnwrap(MetricCardConfig.cards(from: components), "renk/eşik özelleştirmesi basit düzenleyiciden atmamalı")
        XCTAssertEqual(parsed[1], cpu)
        XCTAssertEqual(parsed[2], memory)
    }

    func testCardThresholdsResetWhenScaleChanges() {
        var cpu = MetricCardConfig(.cpu, shown: true, fields: [.cpu, .cpuTemp])
        cpu.effectiveThresholds = Thresholds(warning: 0.3, critical: 0.5)
        cpu.set(.cpuTemp, selected: false)
        XCTAssertEqual(cpu.thresholds, Thresholds(warning: 0.3, critical: 0.5), "öndeki değer aynı: korunur")
        cpu.set(.cpuTemp, selected: true)
        cpu.set(.cpu, selected: false)
        XCTAssertNil(cpu.thresholds, "% → °C: varsayılana döner")
        XCTAssertEqual(cpu.effectiveThresholds, DataField.cpuTemp.defaultThresholds)
        cpu.effectiveThresholds = DataField.cpuTemp.defaultThresholds
        XCTAssertNil(cpu.thresholds, "varsayılana eşit eşik nil saklanır (gidiş-dönüş için)")
    }

    func testAdvancedThresholdsOnMonochromeCardStillRoundTrip() throws {
        var components = MetricCardConfig.components(for: MetricCardConfig.defaults)
        let i = try XCTUnwrap(components.firstIndex { $0.primary == .memoryUsed })
        components[i].thresholds = Thresholds(warning: 0.5, critical: 0.9)
        let cards = try XCTUnwrap(MetricCardConfig.cards(from: components))
        XCTAssertEqual(cards.first { $0.kind == .memory }?.thresholds, Thresholds(warning: 0.5, critical: 0.9))
    }
}
