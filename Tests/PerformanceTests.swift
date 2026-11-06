import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Pil/CPU gerilemelerini yakalayan ucuz testler: önbellekler doğru mu, değişmeyen değer yeniden çizim üretmiyor mu,
/// çizim yolu bütçenin altında mı. `measure` blokları Xcode'da taban çizgisi olarak ayarlanabilir.
@MainActor
final class PerformanceTests: XCTestCase {
    private let values = WidgetValues.sample

    /// Kullanıcının gerçek düzenine benzer: 4 ayrı öğe, ikili satırlar, sıcaklık.
    private func components() -> [MenuBarComponent] {
        [
            MenuBarComponent(.memoryUsed, visual: .stacked2, showLabel: true),
            MenuBarComponent(.cpu, .cpuTemp, visual: .stacked2, showLabel: true),
            MenuBarComponent(.gpu, .gpuTemp, visual: .stacked2, showLabel: true),
            MenuBarComponent(.diskFree, visual: .stacked2, showLabel: true),
        ]
    }

    // MARK: WidgetText önbelleği

    func testCachedWidthEqualsDirectMeasurement() {
        for role in WidgetText.Role.allCases {
            for text in ["", "46%", "1,2 MB/s", "128 GB", "54 °C"] {
                let direct = (text as NSString).size(withAttributes: [.font: WidgetText.font(role)]).width
                XCTAssertEqual(WidgetText.rawWidth(text, role), direct, accuracy: 0.0001)
                XCTAssertEqual(WidgetText.width(text, role), ceil(direct), accuracy: 0.0001)
                // İkinci çağrı (önbellekten) aynı sonucu vermeli.
                XCTAssertEqual(WidgetText.rawWidth(text, role), direct, accuracy: 0.0001)
            }
        }
    }

    func testFontIsReusedAcrossCalls() {
        for role in WidgetText.Role.allCases {
            XCTAssertTrue(WidgetText.font(role) === WidgetText.font(role), "\(role) her çağrıda yeniden üretiliyor")
        }
    }

    // MARK: Çizim atlama (render key)

    func testRenderKeyIsStableForIdenticalValues() {
        let config = MenuBarConfig(components: components(), displayMode: .separate)
        for c in config.enabledComponents {
            let a = MenuBarRenderKey(components: [c], config: config, values: values)
            let b = MenuBarRenderKey(components: [c], config: config, values: values)
            XCTAssertEqual(a, b)
        }
    }

    func testRenderKeyIgnoresChangesBelowDisplayedPrecision() {
        let config = MenuBarConfig(components: components(), displayMode: .separate)
        let cpu = config.enabledComponents[1]
        var shifted = values
        shifted.cpu = values.cpu + 0.001 // %46,0 → %46,1: görünen metin ve 1 puanlık seviye aynı
        XCTAssertEqual(MenuBarRenderKey(components: [cpu], config: config, values: values),
                       MenuBarRenderKey(components: [cpu], config: config, values: shifted))
        shifted.cpu = values.cpu + 0.05
        XCTAssertNotEqual(MenuBarRenderKey(components: [cpu], config: config, values: values),
                          MenuBarRenderKey(components: [cpu], config: config, values: shifted))
    }

    // MARK: Çizim yolu bütçeleri

    /// Tek öğenin bitmap'i: 4 öğe × 50 tekrar bu makinede tipik olarak <0,3 sn; cömert üst sınır CI gürültüsüne dayanır.
    func testComposeBudget() {
        let config = MenuBarConfig(components: components(), displayMode: .separate)
        let items = config.enabledComponents
        _ = MenuBarComposer.image(for: items, config: config, values: values) // ısınma
        let start = ContinuousClock.now
        for _ in 0..<50 {
            for c in items {
                let image = MenuBarComposer.image(for: [c], config: config, values: values)
                _ = MenuBarComposer.bitmap(image, appearance: NSAppearance(named: .aqua) ?? .currentDrawing(), scale: 2)
            }
        }
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(elapsed, .seconds(3), "menü çubuğu çizimi çok yavaş: \(elapsed)")
    }

    func testMeasureStatusItemRender() {
        let config = MenuBarConfig(components: components(), displayMode: .separate)
        let items = config.enabledComponents
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            for _ in 0..<20 {
                for c in items {
                    let key = MenuBarRenderKey(components: [c], config: config, values: values)
                    _ = key
                    let image = MenuBarComposer.image(for: [c], config: config, values: values)
                    _ = MenuBarComposer.bitmap(image, appearance: NSAppearance(named: .aqua) ?? .currentDrawing(), scale: 2)
                }
            }
        }
    }

    func testMeasureRenderKeyOnly() {
        let config = MenuBarConfig(components: components(), displayMode: .separate)
        let items = config.enabledComponents
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<500 {
                for c in items { _ = MenuBarRenderKey(components: [c], config: config, values: values) }
            }
        }
    }

    // MARK: Sayfa gövdeleri

    /// Genel bakış "Canlı" bölümü (saniyede bir değişen tek bölüm) bir kez kurulup yerleşir.
    func testMeasureOverviewLiveSectionLayout() {
        let data = PanelData.sample
        let host = NSHostingView(rootView: OverviewLiveSection(data: data).frame(width: 760))
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 760, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        host.layoutSubtreeIfNeeded()
        measure(metrics: [XCTClockMetric()]) {
            var d = data
            d.cpuHistory.append(Double.random(in: 0...1)) // her turda farklı girdi
            host.rootView = OverviewLiveSection(data: d).frame(width: 760)
            host.layoutSubtreeIfNeeded()
        }
        window.close()
    }

    func testMeasurePanelDataSampleCopy() {
        let data = PanelData.sample
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<2_000 { _ = SystemMetric.all(data, showTemperatures: true) }
        }
    }

    // MARK: Panel (menü çubuğu paneli açıkken saniyede bir)

    func testMeasurePanelDataFromModel() {
        let model = AppModel()
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<200 { _ = PanelData(model: model) }
        }
    }

    func testMeasurePanelViewLayout() {
        let model = AppModel()
        let host = NSHostingView(rootView: PanelView(model: model, openApp: {}, openSettings: {}, onSizeChange: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 372, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        host.layoutSubtreeIfNeeded()
        measure(metrics: [XCTClockMetric()]) {
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            _ = host.fittingSize
        }
        window.close()
    }
    // MARK: Boşta maliyet (kayıt dışı regresyon bekçileri)

    func testIdleIngestKeepsWindowEmptyAndRotatesOut() {
        let engine = UsageEngine(store: UsageStore())
        let minute = Int(Date.now.timeIntervalSince1970 / 60)
        engine.ingest([UsageBucket(app: "/Applications/A.app", signingID: "", host: "a.example.com", kind: .direct, expensive: false,
                                   minute: minute, bytesIn: 1_000, bytesOut: 10)])
        XCTAssertEqual(engine.last60.count, 1)
        // 60 sn sonra pencere boşalmalı (kısayol yanlışlıkla eski değeri tutmamalı).
        engine.ingest([], seconds: 30)
        XCTAssertEqual(engine.last60.count, 1)
        engine.ingest([], seconds: 30)
        XCTAssertTrue(engine.last60.isEmpty)
        // Boşta çağrılar sonuçsuzdur.
        for _ in 0..<100 { engine.ingest([], seconds: 5) }
        XCTAssertTrue(engine.last60.isEmpty)
    }

    func testIdleIngestBudget() {
        let engine = UsageEngine(store: UsageStore())
        let start = ContinuousClock.now
        for _ in 0..<20_000 { engine.ingest([], seconds: 5) }
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(elapsed, .milliseconds(500), "boş ingest çok yavaş: \(elapsed)")
    }

    func testPageDataWithoutLiveMetricsIsStableAndSkipsMetrics() {
        let model = AppModel()
        let a = PanelData(model: model, live: false)
        let b = PanelData(model: model, live: false)
        XCTAssertNil(a.snapshot)
        XCTAssertTrue(a.cpuHistory.isEmpty && a.downHistory.isEmpty && a.temperatureHistory.isEmpty)
        XCTAssertEqual(a, b, "canlı olmayan sayfa verisi ardışık okumalarda eşit olmalı (aksi halde .equatable() işe yaramaz)")
    }
}
