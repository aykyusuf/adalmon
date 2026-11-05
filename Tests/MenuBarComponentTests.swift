import XCTest
@testable import Adalmon

final class MenuBarComponentTests: XCTestCase {
    private let v = WidgetValues.sample

    // MARK: Field formatting

    func testFieldFormatting() {
        XCTAssertEqual(DataField.cpu.text(v, showUnits: true), "%46")
        XCTAssertEqual(DataField.cpuTemp.text(v, showUnits: true), "54 °C")
        XCTAssertEqual(DataField.cpuTemp.text(v, showUnits: false), "54°")
        XCTAssertEqual(DataField.cpuMaxTemp.text(v, showUnits: true), "71 °C")
        XCTAssertEqual(DataField.download.text(v, showUnits: true), "18,4 MB/s")
        XCTAssertEqual(DataField.upload.text(v, showUnits: true), "1,2 MB/s")
        XCTAssertEqual(DataField.downloadToday.text(v, showUnits: true), "4,3 GB")
        XCTAssertEqual(DataField.uploadLast60.text(v, showUnits: true), "52,0 MB")
        XCTAssertEqual(DataField.mobileUsed.text(v, showUnits: true), "1,8/3 GB")
        XCTAssertEqual(DataField.mobileRemaining.text(v, showUnits: true), "1,2 GB")
        XCTAssertEqual(DataField.memoryFree.text(v, showUnits: true, unit: .mb), "3604 MB")
        XCTAssertEqual(DataField.memoryFree.text(v, showUnits: true), "3,5 GB")
        XCTAssertEqual(DataField.memoryUsed.text(v, showUnits: true, unit: .gb), "12,5 GB")
        XCTAssertEqual(DataField.memoryUsed.text(v, showUnits: false, unit: .gb), "12,5 G")
        XCTAssertEqual(DataField.diskFree.text(v, showUnits: true, unit: .gb), "378 GB")
        XCTAssertEqual(DataField.memoryPressure.text(v, showUnits: true), "Normal")
        XCTAssertEqual(DataField.connection.text(v, showUnits: true), "Wi-Fi")

        var missing = v
        missing.temperature = nil
        missing.gpu = nil
        XCTAssertEqual(DataField.gpuTemp.text(missing, showUnits: true), "—")
        XCTAssertEqual(DataField.gpu.text(missing, showUnits: true), "–")
        XCTAssertEqual(DataField.gpuTemp.level(missing), 0)
    }

    func testFreeAndRemainingLevelsAreInverted() {
        XCTAssertTrue(DataField.memoryFree.isInverted)
        XCTAssertEqual(DataField.memoryFree.level(v), 0.78, accuracy: 0.001, "1 - free/total")
        XCTAssertEqual(DataField.memoryUsed.level(v), 0.78, accuracy: 0.001)
        XCTAssertEqual(DataField.diskFree.level(v), 1 - 377_971_782_041 / 994_662_584_320, accuracy: 0.0001)
        XCTAssertEqual(DataField.mobileRemaining.level(v), 0.6, accuracy: 1e-9)

        var lowFree = v
        lowFree.memUsed = lowFree.memTotal - 100_000_000
        XCTAssertGreaterThan(DataField.memoryFree.level(lowFree), 0.99, "little free memory reads as high (red)")
        let threshold = MenuBarComponent(.memoryFree, colorMode: .threshold)
        XCTAssertEqual(WidgetPalette.valueText(for: threshold, field: .memoryFree, level: DataField.memoryFree.level(lowFree),
                                               connection: .online), .systemRed)

        var empty = v
        empty.memTotal = 0
        empty.memUsed = 0
        empty.diskTotal = 0
        empty.mobileCap = 0
        XCTAssertEqual(DataField.memoryFree.level(empty), 0, "unknown total must not read as full")
        XCTAssertEqual(DataField.diskFree.level(empty), 0)
        XCTAssertEqual(DataField.mobileRemaining.level(empty), 0)

        var over = v
        over.mobileUsed = over.mobileCap + 500_000_000
        XCTAssertEqual(DataField.mobileRemaining.rawValue(over), 0)
        XCTAssertEqual(DataField.mobileRemaining.level(over), 1)
    }

    // MARK: Migration

    private let round2JSON = #"""
    {"items":[
      {"id":"00000000-0000-0000-0000-000000000001","metric":"connection","style":"dot"},
      {"id":"00000000-0000-0000-0000-000000000002","metric":"network","style":"speedTwoLine","networkDirection":"both","networkSource":"speed"},
      {"id":"00000000-0000-0000-0000-000000000003","metric":"network","style":"networkChart","colorMode":"accent"},
      {"id":"00000000-0000-0000-0000-000000000004","metric":"network","style":"text","networkSource":"mobileToday"},
      {"id":"00000000-0000-0000-0000-000000000005","metric":"temperature","style":"ring","temperatureSource":"gpu","colorMode":"threshold","showLabel":true},
      {"id":"00000000-0000-0000-0000-000000000006","metric":"cpu","style":"verticalBar","enabled":false,"colorMode":"custom",
       "customColor":{"red":0.1,"green":0.2,"blue":0.3,"alpha":1},"colorizeText":true,"showValue":false,
       "thresholds":{"warning":0.5,"critical":0.9}},
      {"id":"00000000-0000-0000-0000-000000000007","metric":"memory","style":"stacked"},
      {"id":"00000000-0000-0000-0000-000000000008","metric":"network","style":"text","networkDirection":"upload","networkSource":"today"}
    ],"displayMode":"separate","spacing":8,"showUnits":false}
    """#

    func testMigrationFromRound2JSON() throws {
        let config = try JSONDecoder().decode(MenuBarConfig.self, from: Data(round2JSON.utf8))
        let c = config.components
        XCTAssertEqual(c.count, 8)
        XCTAssertEqual(config.displayMode, .separate)
        XCTAssertEqual(config.spacing, 8)
        XCTAssertFalse(config.showUnits)
        XCTAssertEqual(c[0].id.uuidString, "00000000-0000-0000-0000-000000000001", "ids carry over (status item autosave names)")
        XCTAssertEqual(c[0].primary, .connection)
        XCTAssertEqual(c[0].visual, .dot)
        XCTAssertEqual([c[1].primary, c[1].secondary], [.upload, .download])
        XCTAssertEqual(c[1].visual, .stacked2)
        XCTAssertTrue(c[1].showLabel, "arrows identify the two lines")
        XCTAssertEqual([c[2].primary, c[2].secondary], [.download, .upload])
        XCTAssertEqual(c[2].visual, .sparkline)
        XCTAssertEqual(c[2].colorMode, .accent)
        XCTAssertFalse(c[2].showValue)
        XCTAssertEqual(c[3].primary, .mobileUsed)
        XCTAssertNil(c[3].secondary)
        XCTAssertEqual(c[4].primary, .gpuTemp)
        XCTAssertEqual(c[4].visual, .ring)
        XCTAssertEqual(c[4].thresholds, Thresholds(warning: 0.70, critical: 0.85))
        XCTAssertTrue(c[4].showLabel)
        XCTAssertEqual(c[5].primary, .cpu)
        XCTAssertEqual(c[5].visual, .bar)
        XCTAssertFalse(c[5].enabled)
        XCTAssertFalse(c[5].showValue)
        XCTAssertEqual(c[5].colorMode, .custom)
        XCTAssertEqual(c[5].customColor, RGBAColor(red: 0.1, green: 0.2, blue: 0.3))
        XCTAssertEqual(c[5].colorTarget, .both)
        XCTAssertEqual(c[5].thresholds, Thresholds(warning: 0.5, critical: 0.9))
        XCTAssertEqual(c[6].primary, .memoryPercent)
        XCTAssertEqual(c[6].visual, .stacked2)
        XCTAssertEqual(c[7].primary, .uploadToday)
        XCTAssertTrue(c.allSatisfy(\.isValid))
        XCTAssertEqual(config.enabledComponents.count, 7)

        let data = try JSONEncoder().encode(config)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["components"])
        XCTAssertNil(object["items"], "re-encoding drops the legacy key")
        XCTAssertEqual(try JSONDecoder().decode(MenuBarConfig.self, from: data), config)
    }

    @MainActor
    func testStoreMigratesSavedRound2Data() throws {
        let suite = "adalmon.tests.\(#function)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }
        d.set(Data(round2JSON.utf8), forKey: MenuBarConfigStore.defaultsKey)
        let store = MenuBarConfigStore(defaults: d)
        XCTAssertEqual(store.config.components.count, 8)
        let saved = try XCTUnwrap(d.data(forKey: MenuBarConfigStore.defaultsKey))
        XCTAssertTrue(String(decoding: saved, as: UTF8.self).contains("\"components\""))
        XCTAssertEqual(MenuBarConfigStore(defaults: d).config, store.config)
    }

    func testMigrationOfEveryLegacyCombinationIsValid() {
        for metric in MetricKind.allCases {
            for style in metric.supportedStyles {
                for direction in NetworkDirection.allCases {
                    for source in NetworkValueSource.allCases {
                        let item = MenuBarItemConfig(metric: metric, style: style, networkDirection: direction, networkSource: source)
                        let c = MenuBarComponent(legacy: item)
                        XCTAssertTrue(c.isValid, "\(metric) \(style) \(direction) \(source)")
                        XCTAssertEqual(c.id, item.id)
                    }
                }
            }
        }
    }

    // MARK: Library

    func testLibraryComponentsAreValid() {
        let entries = ComponentLibrary.entries
        XCTAssertGreaterThanOrEqual(entries.count, 30)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count, "unique ids")
        XCTAssertEqual(Set(entries.map(\.component.id)).count, entries.count)
        for category in FieldCategory.allCases {
            XCTAssertFalse(ComponentLibrary.entries(in: category).isEmpty, "\(category)")
        }
        let config = MenuBarConfig.default
        for entry in entries {
            XCTAssertTrue(entry.component.isValid, entry.id)
            XCTAssertEqual(entry.component.normalized(), entry.component, entry.id)
            XCTAssertGreaterThan(ComponentRenderer.width(of: entry.component, config: config, values: v), 4, entry.id)
            XCTAssertFalse(entry.title.isEmpty)
        }
        XCTAssertTrue(entries.contains { $0.component.primary == .cpu && $0.component.secondary == .cpuTemp && $0.component.visual == .stacked2 })
        XCTAssertTrue(entries.contains { $0.component.primary == .download && $0.component.secondary == nil })
        XCTAssertTrue(entries.contains { $0.component.primary == .upload && $0.component.secondary == nil })
        XCTAssertTrue(entries.contains { $0.component.primary == .memoryFree && $0.component.unit == .mb })
    }

    func testVisualSupportRules() {
        XCTAssertFalse(ComponentVisual.sparkline.supports(primary: .diskFree, secondary: nil))
        XCTAssertTrue(ComponentVisual.sparkline.supports(primary: .download, secondary: .upload))
        XCTAssertFalse(ComponentVisual.hbar.supports(primary: .cpu, secondary: .cpuTemp))
        XCTAssertFalse(ComponentVisual.dot.supports(primary: .cpu, secondary: .gpu))
        XCTAssertFalse(ComponentVisual.ring.supports(primary: .connection, secondary: nil))
        XCTAssertTrue(ComponentVisual.stacked2.supports(primary: .cpu, secondary: .cpuTemp))
        var c = MenuBarComponent(.cpu, .cpuTemp, visual: .stacked2)
        c.visual = .hbar
        XCTAssertNil(c.normalized().secondary)
        c = MenuBarComponent(.cpu, visual: .sparkline)
        c.primary = .diskFree
        XCTAssertEqual(c.normalized().visual, .text)
    }

    // MARK: Width stability

    func testWidthsAreStableAcrossValues() {
        var low = WidgetValues.sample
        low.cpu = 0.01; low.down = 3; low.up = 0; low.mobileUsed = 0; low.temperature = nil; low.downToday = 5
        low.memUsed = 10; low.diskFree = 10; low.diskRead = 0; low.gpu = nil; low.gpuMemory = nil; low.pressure = .normal
        var high = WidgetValues.sample
        high.cpu = 1; high.down = 99_900_000; high.up = 88_800_000; high.mobileUsed = 2_950_000_000
        high.temperature = TemperatureStats(cpu: 104, cpuMax: 108, gpu: 99, ssd: 70, battery: 45)
        high.memUsed = high.memTotal - 1; high.diskFree = high.diskTotal - 1; high.diskWrite = 900_000_000
        high.pressure = .critical; high.upToday = 99_000_000_000

        var stacked = [MenuBarComponent(.cpu, .cpuTemp, visual: .stacked2, showLabel: true),
                       MenuBarComponent(.cpu, .cpuTemp, visual: .stacked2),
                       MenuBarComponent(.memoryUsed, .memoryFree, visual: .stacked2, showLabel: true, unit: .mb),
                       MenuBarComponent(.cpu, visual: .stacked2, showLabel: true)]
        stacked += ComponentLibrary.entries.map(\.component) + MenuBarPreset.allCases.flatMap(\.components)
        for showUnits in [true, false] {
            var config = MenuBarConfig.default
            config.showUnits = showUnits
            for c in stacked {
                XCTAssertEqual(ComponentRenderer.width(of: c, config: config, values: low),
                               ComponentRenderer.width(of: c, config: config, values: high),
                               "\(c.title) \(c.visual) units:\(showUnits)")
            }
        }
    }

    func testStacked2WidthIsMaxOfLines() {
        let config = MenuBarConfig.default
        let both = ComponentRenderer.width(of: MenuBarComponent(.cpu, .download, visual: .stacked2), config: config, values: v)
        let rateOnly = ComponentRenderer.width(of: MenuBarComponent(.download, .upload, visual: .stacked2), config: config, values: v)
        XCTAssertEqual(both, rateOnly, "the wider line (rate) decides the width")
    }
}
