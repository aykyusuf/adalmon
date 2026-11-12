import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Gerçekçi sahte geçmiş: 14 gün dakikalık seri + 90 güne yayılan günlük satırlar.
enum BatteryPreviewSeed {
    static func populate(_ store: UsageStore, now: Date = .now) async {
        let cal = UsageStore.keyCalendar
        let nowTs = Int(now.timeIntervalSince1970)
        let start = nowTs - 14 * 86_400
        var samples: [BatterySample] = []
        var deltas: [BatteryEnergyTracker.Delta] = []
        var screen: [String: Int] = [:]
        var tracker = BatteryEnergyTracker()
        var level = 100.0
        for ts in stride(from: start, through: nowTs, by: 60) {
            let d = Date(timeIntervalSince1970: TimeInterval(ts))
            let c = cal.dateComponents([.hour, .minute, .day], from: d)
            let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
            let daysAgo = Double(nowTs - ts) / 86_400
            let factor = 0.85 + 0.3 * abs(sin(Double(c.day ?? 1)))
            let plugged = h < 8.8 || (h >= 17.5 && h < 19.5) || h >= 22.5
            if plugged { level = min(100, level + 0.5) } else { level -= (h < 17.5 ? 6.6 : 3.8) * factor / 60 }
            level = max(8, level)
            let charging = plugged && level < 100
            let awake = (h >= 9 && h < 17.5) || (h >= 19.5 && h < 22) || (h >= 8.8 && h < 9)
            let key = UsageStore.dayKey(d, calendar: cal)
            if awake { screen[key, default: 0] += 60 }
            let temp = 26 + 4 * sin(h / 24 * 2 * .pi - 1.2) + (charging ? 4 : 0) + (!plugged && awake ? 3 : 0)
            samples.append(BatterySample(
                ts: ts, pct: Int(level.rounded()), charging: charging, plugged: plugged, tempC: temp, voltageMV: 11_800 + Int(level) * 10,
                amperageMA: charging ? 2_900 : (plugged ? 0 : -1_300), systemMW: awake ? 14_000 : 4_000, adapterW: plugged ? 68 : nil,
                rawMaxMAh: 5_132 + Int(daysAgo * 12), nominalMAh: 5_284 + Int(daysAgo * 12), cycles: 178 - Int(daysAgo * 0.65)))
            if let delta = tracker.consume(level: Int(level.rounded()), day: key) { deltas.append(delta) }
        }
        await store.recordBattery(samples: samples, deltas: deltas, screen: screen.map { .init(day: $0.key, seconds: $0.value) })
        // Eski günler: kapasite/döngü eğrisi + enerji + ekran süresi.
        var olderSamples: [BatterySample] = []
        var olderDeltas: [BatteryEnergyTracker.Delta] = []
        var olderScreen: [ScreenOnClock.DaySeconds] = []
        for back in 15...90 {
            guard let day = cal.date(byAdding: .day, value: -back, to: now) else { continue }
            let noon = Int(cal.startOfDay(for: day).timeIntervalSince1970) + 43_200
            let key = UsageStore.dayKey(day, calendar: cal)
            olderSamples.append(BatterySample(ts: noon, pct: 60, tempC: 27 + 3 * sin(Double(back)), rawMaxMAh: 5_132 + Int(Double(back) * 9.5),
                                              nominalMAh: 5_284 + Int(Double(back) * 9.5), cycles: max(20, 178 - Int(Double(back) * 0.7))))
            olderDeltas.append(.init(day: key, consumedPercent: 45 + 40 * abs(sin(Double(back))), chargedPercent: 0))
            olderScreen.append(.init(day: key, seconds: 3_600 * 4 + Int(3_600 * 5 * abs(cos(Double(back))))))
        }
        await store.recordBattery(samples: olderSamples, deltas: olderDeltas, screen: olderScreen)
    }
}

@MainActor
final class BatteryPreviewTests: XCTestCase {
    private func outputDir() throws -> URL {
        let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        let dir = env.map { URL(filePath: $0) } ?? FileManager.default.temporaryDirectory.appending(path: "battery-previews")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var wantsPreviews: Bool { !(ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"] ?? "").isEmpty }

    @discardableResult
    private func snapshot<V: View>(_ view: V, size: NSSize?, name: String, wait: Double = 0.4, dark: Bool = true) async throws -> NSSize {
        let host = NSHostingView(rootView: view.background(dark ? Color(white: 0.11) : Color(white: 0.96)).preferredColorScheme(dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: size?.width ?? 600, height: size?.height ?? 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        var final = size ?? host.fittingSize
        if size == nil { host.frame = NSRect(origin: .zero, size: final); window.setContentSize(final) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(wait))
        host.layoutSubtreeIfNeeded()
        final = size ?? host.fittingSize
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = try outputDir().appending(path: "\(name).png")
        try png.write(to: url)
        print("BATTERY_PREVIEW: \(url.path())")
        window.close()
        return final
    }

    // MARK: Panel

    func testPanelBatterySectionFitsAndRenders() async throws {
        var data = PanelData.sample
        data.battery = .sampleCharging
        data.batteryApps = [.init(app: "a", name: "Safari", share: 0.34), .init(app: "b", name: "Xcode", share: 0.22), .init(app: "c", name: "Chrome", share: 0.11)]
        let content = PanelContent(data: data, config: .constant(PanelConfig()), actions: .inert).background(Color(white: 0.16))
        let size = try await snapshot(content, size: nil, name: "bat1-panel-charging")
        XCTAssertLessThanOrEqual(size.height, 900, "Pil bölümü paneli aşırı büyütmemeli")
        var discharge = data
        discharge.battery = .sample
        let collapsed = PanelConfig(collapsed: [.battery])
        let base = PanelContent(data: discharge, config: .constant(PanelConfig(collapsed: [])), actions: .inert).background(Color(white: 0.16))
        let sizeOpen = try await snapshot(base, size: nil, name: "bat1-panel-battery")
        let sizeCollapsed = try await snapshot(PanelContent(data: discharge, config: .constant(collapsed), actions: .inert).background(Color(white: 0.16)),
                                               size: nil, name: "bat1-panel-collapsed")
        XCTAssertLessThan(sizeCollapsed.height + 100, sizeOpen.height, "daraltılınca belirgin küçülmeli")
        // Bölüm kapatılabilir.
        var hidden = PanelConfig()
        hidden.setVisible(.battery, false)
        XCTAssertFalse(hidden.visibleSections.contains(.battery))
        // Eski kayıtlı yapılandırma (battery bölümü yok) çözülünce bölüm eklenir.
        let legacy = try JSONDecoder().decode(PanelConfig.self, from: Data(#"{"sections":[{"section":"system","isVisible":true}]}"#.utf8))
        XCTAssertTrue(legacy.sections.contains { $0.section == .battery })
    }

    // MARK: Sayfa

    func testBatteryPageRendersWithHistory() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "batp-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UsageStore(path: dir.appending(path: "u.sqlite").path)
        await BatteryPreviewSeed.populate(store)
        let count = await store.batteryRowCount()
        XCTAssertGreaterThan(count, 20_000)
        let monitor = BatteryMonitor(preview: .sampleCharging, store: store)
        monitor.energyApps = [.init(app: "a", name: "Safari", share: 0.34), .init(app: "b", name: "Xcode", share: 0.22),
                              .init(app: "c", name: "Google Chrome", share: 0.14), .init(app: "d", name: "WindowServer", share: 0.09)]
        let router = SettingsRouter(isDockModeOn: { true })
        let page = BatteryPage(monitor: monitor, store: store, router: router)
        guard wantsPreviews else { return }
        try await snapshot(page.frame(width: 1400, height: 900), size: NSSize(width: 1400, height: 900), name: "bat1-page-1400x900", wait: 2.5)
        try await snapshot(page.frame(width: 1400, height: 2700), size: NSSize(width: 1400, height: 2700), name: "bat1-page-full", wait: 2.5)
        let low = BatteryMonitor(preview: .sample, store: store)
        try await snapshot(BatteryPage(monitor: low, store: store, router: router).frame(width: 1000, height: 1500),
                           size: NSSize(width: 1000, height: 1500), name: "bat1-page-onbattery-narrow", wait: 2.5)
    }

    func testMainWindowShowsBatterySectionWithRealReading() async throws {
        guard wantsPreviews else { return }
        let model = AppModel()
        model.battery.start()
        defer { model.battery.stop() }
        let router = SettingsRouter(isDockModeOn: { true })
        router.selectedMainSection = .battery
        let view = MainWindowView(model: model, source: .fixed(.sample), actions: .inert, router: router) { settings in
            SettingsDetailView(section: settings, model: model)
        }
        try await snapshot(view.frame(width: 1400, height: 900), size: NSSize(width: 1400, height: 900), name: "bat1-mainwindow-real", wait: 2.5)
        XCTAssertEqual(MainSection.battery.shortcutKey, "7")
        XCTAssertTrue(MainSection.pages.contains(.battery))
    }

    // MARK: Menü çubuğu

    func testMenuBarBatteryVariants() async throws {
        func comp(_ options: BatteryGlyphOptions) -> MenuBarComponent {
            MenuBarComponent(.batteryLevel, visual: .batteryCapsule, battery: options)
        }
        func values(_ r: BatteryReading) -> WidgetValues {
            var v = WidgetValues.sample
            v.battery = BatteryGlyphState(r)
            return v
        }
        var low = BatteryReading.sample; low.level = 15; low.timeToEmptyMinutes = 38
        var critical = BatteryReading.sample; critical.level = 5; critical.timeToEmptyMinutes = 12
        var full = BatteryReading.sampleCharging; full.level = 100; full.isCharging = false; full.isFullyCharged = true; full.timeToFullMinutes = nil
        var lpm = BatteryReading.sample; lpm.lowPowerMode = true
        let variants: [(String, MenuBarComponent, BatteryReading)] = [
            ("Pilde %78", comp(.init()), .sample),
            ("Pilde + süre", comp(.init(showTime: true)), .sample),
            ("Şarjda + süre", comp(.init(showTime: true)), .sampleCharging),
            ("Düşük %15", comp(.init(showTime: true)), low),
            ("Kritik %5", comp(.init(showTime: true)), critical),
            ("Tam şarjlı", comp(.init(showTime: true)), full),
            ("Düşük güç modu", comp(.init()), lpm),
            ("Büyük", comp(.init(showTime: true, size: .large)), .sampleCharging),
            ("Küçük", comp(.init(showTime: true, size: .small)), .sample),
            ("Durum rengi kapalı", comp(.init(showTime: true, statusColors: false)), critical),
            ("Animasyon hafif", comp(.init(motion: .light)), .sample),
            ("Animasyon kapalı", comp(.init(motion: .off)), .sample),
        ]
        var widths: [CGFloat] = []
        let rows = VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(variants.enumerated()), id: \.offset) { _, v in
                let config = MenuBarConfig(components: [v.1])
                let vals = values(v.2)
                let image = MenuBarComposer.image(for: [v.1], config: config, values: vals, appearance: .darkAqua, zoom: 4)
                HStack(spacing: 16) {
                    Text(v.0).font(.callout).foregroundStyle(.white.opacity(0.8)).frame(width: 170, alignment: .leading)
                    Image(nsImage: MenuBarComposer.bitmap(image, appearance: NSAppearance(named: .darkAqua)!, scale: 1)).interpolation(.high)
                        .padding(.horizontal, 12).background(Color(white: 0.12), in: .rect(cornerRadius: 8))
                }
            }
        }
        .padding(20).background(Color(white: 0.2))
        for v in variants { widths.append(ComponentRenderer.width(of: v.1, config: MenuBarConfig(components: [v.1]), values: values(v.2))) }
        try await snapshot(rows, size: nil, name: "bat1-menubar-variants")
        XCTAssertTrue(widths.allSatisfy { $0 > 20 && $0 < 120 }, "\(widths)")
        XCTAssertGreaterThan(widths[2], widths[0], "şimşek + süre genişletir")
        // Bileşen kütüphanesinde pil girdileri var ve geçerli.
        let entries = ComponentLibrary.entries(in: .battery)
        XCTAssertGreaterThanOrEqual(entries.count, 4)
        XCTAssertTrue(entries.allSatisfy { $0.component.isValid })
    }

    // MARK: Uyarı balonu ve kenar parlaması

    func testAlertBubbleAndGlowRender() async throws {
        let events: [BatteryAlertEvent] = [
            .init(kind: .low(20), level: 15, minutes: 9, action: .init()),
            .init(kind: .low(5), level: 5, minutes: 4, action: .init()),
            .init(kind: .charged(100), level: 100, minutes: nil, action: .init()),
            .init(kind: .pluggedIn, level: 64, minutes: 40, action: .init()),
            .init(kind: .unplugged, level: 100, minutes: 612, action: .init()),
        ]
        XCTAssertEqual(events[0].message, "%15 kaldı · 9 dk")
        let bubbles = VStack(spacing: 14) { ForEach(0..<events.count, id: \.self) { BatteryAlertBubbleView(event: events[$0]) } }
            .padding(30).background(LinearGradient(colors: [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
        try await snapshot(bubbles, size: nil, name: "bat1-alert-bubbles", wait: 1.0)
        let glow = ZStack {
            LinearGradient(colors: [Color(white: 0.18), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
            Text("Kenar parlaması (kritik)").foregroundStyle(.white.opacity(0.5))
            EdgeGlowView(color: .red)
        }
        try await snapshot(glow, size: NSSize(width: 1000, height: 620), name: "bat1-alert-glow", wait: 0.6)
    }

    func testPresenterCreatesWindowsOnlyWhenShownAndReleasesThem() async throws {
        let p = BatteryAlertPresenter()
        XCTAssertFalse(p.isShowingBubble)
        XCTAssertFalse(p.isShowingGlow)
        p.show(.init(kind: .low(20), level: 15, minutes: 9, action: .init(presentation: .bubbleCenter)))
        XCTAssertTrue(p.isShowingBubble)
        p.show(.init(kind: .low(5), level: 5, minutes: 4, action: .init(presentation: .edgeGlow)))
        XCTAssertTrue(p.isShowingGlow)
        p.show(.init(kind: .pluggedIn, level: 5, minutes: nil, action: .init(presentation: .none)))
        p.dismissBubble()
        p.dismissGlow()
        XCTAssertFalse(p.isShowingBubble)
        XCTAssertFalse(p.isShowingGlow)
        XCTAssertTrue(NSApp.windows.filter { $0.isVisible && $0.level == .statusBar && $0.ignoresMouseEvents }.isEmpty, "parlama pencereleri kapatıldı")
    }

    func testSettingsPaneRenders() async throws {
        guard wantsPreviews else { return }
        let model = AppModel()
        try await snapshot(BatteryAlertsSettingsPane(model: model).frame(width: 760, height: 1100), size: NSSize(width: 760, height: 1100),
                           name: "bat1-settings-alerts", wait: 0.8)
    }
}

/// Opt-in PNGs of the charging-bolt styles x colors at a few animation phases (light + dark), at menu bar scale (x8).
/// The real animation is Core Animation (cannot be snapshotted), so phases are drawn here with the same keyframe tables
/// as `BatteryLiquidAnimator.updateBoltAnimation`. Run with TEST_RUNNER_ADALMON_PREVIEW_DIR=<dir>.
@MainActor
final class BatteryBoltPreviewTests: XCTestCase {
    private static let zoom: CGFloat = 8
    private static let phases: [Double] = [0, 0.2, 0.4, 0.6, 0.8]

    private func interpolate(_ values: [Double], _ times: [Double], at t: Double) -> Double {
        for i in 1..<times.count where t <= times[i] {
            let f = (t - times[i - 1]) / max(times[i] - times[i - 1], 1e-9)
            return values[i - 1] + (values[i] - values[i - 1]) * f
        }
        return values.last ?? 1
    }

    private func chargingState() -> BatteryGlyphState {
        var r = BatteryReading.sample
        r.level = 64
        r.isCharging = true
        r.isPluggedIn = true
        r.batteryPowerMW = 15_000
        r.timeToFullMinutes = 40
        r.timeToEmptyMinutes = nil
        var s = BatteryGlyphState(r)
        s.timeText = nil
        return s
    }

    /// Bir hücre: pil + şimşek, verilen stilin `phase` anındaki hali (hücre sol-alt = origin).
    private func drawCell(style: BatteryBoltOptions.Style, tone: BatteryBoltOptions.Tone, phase: Double, at origin: CGPoint,
                          cell: CGSize, state: BatteryGlyphState, ctx: CGContext) {
        let bolt = BatteryBoltOptions(style: style, tone: tone, custom: tone == .custom ? RGBAColor(hex: "#FF4FA3") : nil)
        let options = BatteryGlyphOptions(statusColors: true, size: .medium, motion: .live, style: .liquid, bolt: bolt)
        let m = BatteryGlyph.metrics(.medium)
        let capSize = BatteryGlyph.capsuleSize(m, state)
        let slot = BatteryGlyph.boltSlot(m, state)
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        let content = CGSize(width: slot + capSize.width, height: capSize.height)
        ctx.translateBy(x: (cell.width - content.width) / 2, y: (cell.height - content.height) / 2)
        let capsule = CGRect(x: slot, y: 0, width: capSize.width, height: capSize.height)
        BatteryGlyph.drawCapsule(state, options: options, level: Double(state.level), in: capsule, wave: nil)

        let rect = BatteryGlyph.boltRect(.medium, capsule: capsule)
        let color = BatteryGlyph.boltColor(bolt, statusColors: true, state)
        let path = BatteryGlyph.boltPath(in: rect)
        func fill(_ alpha: CGFloat) {
            color.withAlphaComponent(alpha).setFill()
            path.fill()
        }
        switch style {
        case .auto, .still:
            fill(1)
        case .pulse:
            let times = [0, 0.12, 0.26, 0.4, 0.54, 1.0]
            let opacity = interpolate([1, 0.6, 1, 0.84, 1, 1], times, at: phase)
            let scale = interpolate([1, 1.14, 1, 1.084, 1, 1], times, at: phase)
            ctx.saveGState()
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
            fill(opacity)
            ctx.restoreGState()
        case .shimmer:
            fill(1)
            ctx.saveGState()
            path.addClip()
            let x = interpolate([-0.5, 1.5, 1.5], [0, 0.55, 1], at: phase) * rect.width + rect.minX
            let band = CGRect(x: x - rect.width * 0.45, y: rect.minY, width: rect.width * 0.9, height: rect.height)
            let gradient = NSGradient(colors: [NSColor.white.withAlphaComponent(0), NSColor.white.withAlphaComponent(0.85),
                                               NSColor.white.withAlphaComponent(0)])
            gradient?.draw(in: band, angle: 0)
            ctx.restoreGState()
        case .flow:
            fill(0.3)
            let grow = phase < 0.6 ? 0.5 - 0.5 * cos(.pi * phase / 0.6) : 1
            let fade = interpolate([1, 1, 1, 0], [0, 0.6, 0.85, 1], at: phase)
            ctx.saveGState()
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * grow).clip()
            fill(fade)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    private func render(style: BatteryBoltOptions.Style, dark: Bool, to url: URL) throws {
        let state = chargingState()
        let tones = BatteryBoltOptions.Tone.allCases
        let cell = CGSize(width: 54, height: 18)
        let labelW: CGFloat = 46
        let size = CGSize(width: labelW + cell.width * CGFloat(Self.phases.count), height: cell.height * CGFloat(tones.count) + 14)
        let z = Self.zoom
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * z), pixelsHigh: Int(size.height * z),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
        NSGraphicsContext.saveGraphicsState()
        let gc = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.current = gc
        appearance.performAsCurrentDrawingAppearance {
            (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            CGRect(origin: .zero, size: size).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 5), .foregroundColor: NSColor.labelColor]
            ("\(style.displayName) — fazlar " + Self.phases.map { String(format: "%.1f", $0) }.joined(separator: " / "))
                .draw(at: CGPoint(x: 3, y: size.height - 10), withAttributes: attrs)
            for (row, tone) in tones.enumerated() {
                let y = cell.height * CGFloat(tones.count - 1 - row)
                tone.displayName.draw(at: CGPoint(x: 3, y: y + cell.height / 2 - 3), withAttributes: attrs)
                for (col, phase) in Self.phases.enumerated() {
                    drawCell(style: style, tone: tone, phase: phase, at: CGPoint(x: labelW + cell.width * CGFloat(col), y: y),
                             cell: cell, state: state, ctx: gc.cgContext)
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    func testExportBoltPreviews() throws {
        guard let path = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"] else { return }
        let dir = URL(filePath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for style in BatteryBoltOptions.Style.allCases {
            for dark in [false, true] {
                try render(style: style, dark: dark, to: dir.appending(path: "bolt-\(style.rawValue)-\(dark ? "dark" : "light").png"))
            }
        }
    }
}
