import AppKit
import XCTest
@testable import Adalmon

/// "Dolgulu sıvı pil" menü çubuğu öğesi: ölçüler, kare üretimi, önbellek anahtarı, ayar uyumluluğu, animasyon kararı.
final class BatteryLiquidGlyphTests: XCTestCase {
    private func state(_ level: Int, charging: Bool = false, plugged: Bool = false, full: Bool = false,
                       lowPower: Bool = false) -> BatteryGlyphState {
        var r = BatteryReading.sample
        r.level = level
        r.isCharging = charging
        r.isPluggedIn = plugged || charging
        r.isFullyCharged = full
        r.lowPowerMode = lowPower
        if charging { r.timeToFullMinutes = 40; r.timeToEmptyMinutes = nil }
        var s = BatteryGlyphState(r)
        s.isFull = full
        return s
    }

    // MARK: Ayar

    func testOptionsCodableBackwardCompatible() throws {
        let legacy = try JSONDecoder().decode(BatteryGlyphOptions.self, from: Data(#"{"showTime":true,"size":"large"}"#.utf8))
        XCTAssertEqual(legacy, BatteryGlyphOptions(showTime: true, size: .large, motion: .live), "eski JSON: animasyon varsayılan Canlı")
        let light = try JSONDecoder().decode(BatteryGlyphOptions.self, from: Data(#"{"animation":"light"}"#.utf8))
        XCTAssertEqual(light.motion, .light)
        let bogus = try JSONDecoder().decode(BatteryGlyphOptions.self, from: Data(#"{"animation":"wobble","statusColors":false}"#.utf8))
        XCTAssertEqual(bogus.motion, .live, "bilinmeyen değer varsayılana düşer")
        XCTAssertFalse(bogus.statusColors)
        let off = BatteryGlyphOptions(showTime: false, statusColors: true, size: .small, motion: .off)
        let data = try JSONEncoder().encode(off)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""animation":"off""#), "JSON anahtarı \"animation\"")
        XCTAssertEqual(try JSONDecoder().decode(BatteryGlyphOptions.self, from: data), off)
        XCTAssertEqual(BatteryGlyphOptions.Animation.allCases.map(\.displayName), ["Kapalı", "Hafif", "Canlı"])
    }

    func testCardRoundTripKeepsMotion() throws {
        var cards = MetricCardConfig.defaults
        let index = try XCTUnwrap(cards.firstIndex { $0.kind == .battery })
        cards[index].shown = true
        cards[index].batteryAnimation = .light
        let components = cards.flatMap { $0.components() }
        let capsule = try XCTUnwrap(components.first { $0.visual == .batteryCapsule })
        XCTAssertEqual(capsule.battery.motion, .light)
        let back = try XCTUnwrap(MetricCardConfig.cards(from: components), "Hafif seçimi basit düzenleyiciyi 'gelişmiş'e düşürmez")
        XCTAssertEqual(back.first { $0.kind == .battery }?.batteryAnimation, .light)
    }

    // MARK: Ölçüler ve seviye

    func testMetricsFitMenuBar() {
        let order: [BatteryGlyphOptions.Size] = [.small, .medium, .large]
        let m = order.map(BatteryGlyph.metrics)
        XCTAssertEqual(m[1].body.height, 14, "orta: Juicy pili ~29x14 pt gövde")
        XCTAssertEqual(BatteryGlyph.capsuleSize(m[1], nil).width, 32.2, accuracy: 1, "gövde + uç ≈ 32 pt")
        XCTAssertTrue(m.allSatisfy { $0.body.height <= ComponentRenderer.height - 2 }, "22 pt yuvaya sığar")
        XCTAssertTrue(zip(m, m.dropFirst()).allSatisfy { $0.body.width < $1.body.width && $0.font < $1.font })
        // "⚡100" gövdeye sığar (gerekirse yazı biraz küçülür); "78" tam boyutta kalır.
        for size in order {
            let mm = BatteryGlyph.metrics(size)
            let inner = CGSize(width: mm.body.width - 2 * mm.inset, height: mm.body.height - 2 * mm.inset)
            let font = BatteryGlyph.contentFont(mm, text: "100", bolt: true, innerWidth: inner.width, innerHeight: inner.height)
            let text = ("100" as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(text + BatteryGlyph.boltSize(innerHeight: inner.height).width + BatteryGlyph.boltSpacing, inner.width - 2, "\(size)")
            XCTAssertGreaterThanOrEqual(font.pointSize, mm.font * 0.7)
            XCTAssertEqual(BatteryGlyph.contentFont(mm, text: "78", bolt: false, innerWidth: inner.width, innerHeight: inner.height).pointSize, mm.font)
        }
    }

    func testFillHeightLevels() {
        let h: CGFloat = 14
        let heights = [0, 1, 20, 50, 100].map { BatteryGlyph.fillHeight(level: Double($0), innerHeight: h) }
        XCTAssertEqual(heights[0], 0)
        XCTAssertGreaterThanOrEqual(heights[1], 1.2, "%1 bile ince bir sıvı çizgisi görünür")
        XCTAssertEqual(heights[2], h * 0.2, accuracy: 0.001)
        XCTAssertEqual(heights[3], h / 2, accuracy: 0.001)
        XCTAssertEqual(heights[4], h)
        XCTAssertEqual(heights, heights.sorted())
        XCTAssertEqual(BatteryGlyph.fillHeight(level: 140, innerHeight: h), h)
        XCTAssertEqual(BatteryGlyph.taperedAmplitude(1, level: 100), 1, "tam dolu pilde de dalga var")
        XCTAssertEqual(BatteryGlyph.taperedAmplitude(1, level: 0), 0)
        XCTAssertEqual(BatteryGlyph.taperedAmplitude(1, level: 1), 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(BatteryGlyph.fullLevelDrop(level: 100), 1.5, accuracy: 1e-9)
        XCTAssertEqual(BatteryGlyph.fullLevelDrop(level: 80), 0)
        XCTAssertLessThan(BatteryGlyph.fullLevelDrop(level: 95), 1.5)
        XCTAssertEqual(BatteryGlyph.taperedAmplitude(1, level: 50), 1)
        // Dalga döngüsü N karede kapanır.
        for x in stride(from: CGFloat(0), through: 30, by: 3) {
            XCTAssertEqual(BatteryGlyph.surfaceOffset(x: x, width: 30, phase: 0), BatteryGlyph.surfaceOffset(x: x, width: 30, phase: 1), accuracy: 1e-9)
            XCTAssertLessThanOrEqual(abs(BatteryGlyph.surfaceOffset(x: x, width: 30, phase: 0.3)), 1.0001)
        }
        XCTAssertEqual(BatteryGlyph.pulse(phase: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(BatteryGlyph.pulse(phase: 0.5), 0, accuracy: 1e-9)
    }

    func testStatesTintAndPulse() {
        XCTAssertEqual(BatteryGlyph.tint(statusColors: true, state(64, charging: true)), .systemGreen)
        XCTAssertEqual(BatteryGlyph.tint(statusColors: true, state(5)), .systemRed)
        XCTAssertEqual(BatteryGlyph.tint(statusColors: true, state(15)), .systemOrange)
        XCTAssertNil(BatteryGlyph.tint(statusColors: true, state(100, plugged: true, full: true)))
        XCTAssertEqual(BatteryGlyph.tint(statusColors: true, state(60, lowPower: true)), .systemYellow)
        XCTAssertNil(BatteryGlyph.tint(statusColors: false, state(5)))
        XCTAssertTrue(BatteryGlyph.pulses(state(19)))
        XCTAssertFalse(BatteryGlyph.pulses(state(20)))
        XCTAssertFalse(BatteryGlyph.pulses(state(5, charging: true)), "şarjda nabız yok")
        XCTAssertTrue(BatteryGlyph.showsBolt(state(64, charging: true)))
        XCTAssertFalse(BatteryGlyph.showsBolt(state(100, plugged: true, full: true)), "dolu: şimşek yok")
    }

    // MARK: Kareler ve önbellek

    func testFramesDeterministicAndSized() throws {
        for size in BatteryGlyphOptions.Size.allCases {
            let key = BatteryFrameKey(state: state(50), options: .init(size: size), appearance: .darkAqua, scale: 2)
            let frames = BatteryFrameRenderer.frames(key)
            XCTAssertEqual(frames.count, BatteryGlyph.frameCount)
            let expected = BatteryGlyph.capsuleSize(BatteryGlyph.metrics(size), key.state)
            for f in frames {
                XCTAssertEqual(f.size, expected)
                let rep = try XCTUnwrap(f.representations.first as? NSBitmapImageRep)
                XCTAssertEqual(rep.pixelsWide, Int(ceil(expected.width * 2)))
                XCTAssertEqual(rep.pixelsHigh, Int(ceil(expected.height * 2)))
            }
            XCTAssertEqual(BatteryFrameRenderer.frame(key, index: 3).tiffRepresentation,
                           BatteryFrameRenderer.frame(key, index: 3).tiffRepresentation, "aynı kare aynı pikseller")
            XCTAssertNotEqual(frames[0].tiffRepresentation, frames[12].tiffRepresentation, "dalga kareler arasında hareket eder")
        }
        // Kapalı: düz yüzey, tüm kareler aynı.
        let off = BatteryFrameKey(state: state(50), options: .init(motion: .off), appearance: .darkAqua, scale: 2)
        XCTAssertEqual(BatteryFrameRenderer.frame(off, index: 0).tiffRepresentation, BatteryFrameRenderer.frame(off, index: 12).tiffRepresentation)
        // Seviye aralıkları ve durumlar çizilebilir (boş değil).
        for s in [state(0), state(1), state(20), state(50), state(100), state(64, charging: true), state(100, plugged: true, full: true)] {
            let key = BatteryFrameKey(state: s, options: .init(), appearance: .aqua, scale: 1)
            XCTAssertNotNil(BatteryFrameRenderer.frame(key, index: 0).tiffRepresentation)
        }
    }

    func testFullLevelStillAnimates() {
        for s in [state(100), state(100, charging: true), state(100, plugged: true, full: true), state(97)] {
            let key = BatteryFrameKey(state: s, options: .init(), appearance: .darkAqua, scale: 2)
            let frames = (0..<BatteryGlyph.frameCount).map { BatteryFrameRenderer.frame(key, index: $0).tiffRepresentation }
            XCTAssertGreaterThan(Set(frames).count, BatteryGlyph.frameCount / 2, "seviye \(s.level) kareleri farklı (hareket var)")
            XCTAssertNotEqual(frames[0], frames[6])
            XCTAssertNotEqual(frames[0], frames[12])
        }
        let dead = BatteryFrameKey(state: state(0, charging: true), options: .init(), appearance: .darkAqua, scale: 2)
        XCTAssertEqual(BatteryFrameRenderer.frame(dead, index: 0).tiffRepresentation, BatteryFrameRenderer.frame(dead, index: 12).tiffRepresentation,
                       "%0: sönük")
        let one = BatteryFrameKey(state: state(1), options: .init(), appearance: .darkAqua, scale: 2)
        let a = BatteryFrameRenderer.frame(one, index: 0).tiffRepresentation, b = BatteryFrameRenderer.frame(one, index: 12).tiffRepresentation
        XCTAssertNotNil(a); XCTAssertNotNil(b)
    }

    func testFrameKey() {
        let base = BatteryFrameKey(state: state(78), options: .init(), appearance: .darkAqua, scale: 2)
        var timed = state(78)
        timed.timeText = "9:59"
        XCTAssertEqual(base, BatteryFrameKey(state: timed, options: .init(showTime: true), appearance: .darkAqua, scale: 2),
                       "süre metni ve süre ayarı kareleri değiştirmez → yeniden çizim yok")
        XCTAssertNotEqual(base, BatteryFrameKey(state: state(79), options: .init(), appearance: .darkAqua, scale: 2))
        XCTAssertNotEqual(base, BatteryFrameKey(state: state(78, charging: true), options: .init(), appearance: .darkAqua, scale: 2))
        XCTAssertNotEqual(base, BatteryFrameKey(state: state(78), options: .init(size: .large), appearance: .darkAqua, scale: 2))
        XCTAssertNotEqual(base, BatteryFrameKey(state: state(78), options: .init(statusColors: false), appearance: .darkAqua, scale: 2))
        XCTAssertNotEqual(base, BatteryFrameKey(state: state(78), options: .init(motion: .light), appearance: .darkAqua, scale: 2))
        XCTAssertNotEqual(base, BatteryFrameKey(state: state(78), options: .init(), appearance: .aqua, scale: 2))
        XCTAssertNotEqual(base, BatteryFrameKey(state: state(78), options: .init(), appearance: .darkAqua, scale: 1))
    }

    // MARK: Bileşik görüntü

    func testComposerAnimatedSlot() throws {
        var values = WidgetValues.sample
        values.battery = state(78)
        let mac = MenuBarComponent(.batteryLevel, visual: .batteryCapsule, battery: .init(showTime: true))
        let off = MenuBarComponent(.batteryLevel, visual: .batteryCapsule, battery: .init(motion: .off))
        let cpu = MenuBarComponent(.cpu)
        let device = MenuBarComponent.device("yusuf iphone")
        XCTAssertNil(MenuBarComposer.animatedBatteryIndex(in: [cpu, off, device]), "Kapalı ve cihaz pili animasyonsuz")
        XCTAssertEqual(MenuBarComposer.animatedBatteryIndex(in: [cpu, mac]), 1)
        let config = MenuBarConfig(components: [cpu, mac])
        let rect = try XCTUnwrap(MenuBarComposer.animatedBatteryRect(in: [cpu, mac], config: config, values: values))
        let total = MenuBarComposer.width(of: [cpu, mac], config: config, values: values)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxY, ComponentRenderer.height)
        XCTAssertLessThanOrEqual(rect.maxX, total)
        XCTAssertEqual(rect.size, BatteryGlyph.capsuleSize(BatteryGlyph.metrics(.medium), values.battery))
        // Genişlik fazdan bağımsız; taban + kare = statik çizimle aynı boyut.
        let appearance = NSAppearance(named: .darkAqua)!
        let base = MenuBarComposer.bitmap(MenuBarComposer.image(for: [cpu, mac], config: config, values: values, battery: .hidden),
                                          appearance: appearance, scale: 2)
        let key = BatteryFrameKey(state: values.battery!, options: mac.battery, appearance: .darkAqua, scale: 2)
        let composite = MenuBarComposer.composite(base: base, overlay: BatteryFrameRenderer.frame(key, index: 5), at: rect)
        XCTAssertEqual(composite.size, base.size)
        XCTAssertNotEqual(composite.tiffRepresentation, base.tiffRepresentation)
        // Render anahtarı faza bağlı değil (animasyon tam yeniden hesaplamaya yol açmaz).
        XCTAssertEqual(MenuBarRenderKey(components: [cpu, mac], config: config, values: values),
                       MenuBarRenderKey(components: [cpu, mac], config: config, values: values))
    }

    // MARK: Animasyon kararı ve yaşam döngüsü

    func testAnimationPolicy() {
        typealias P = BatteryAnimationPolicy
        let env = P.Environment()
        XCTAssertEqual(P.plan(mode: .live, hasAnimatedItem: true, charging: false, env: env), P.Plan(fps: 15, step: 1))
        XCTAssertEqual(P.plan(mode: .live, hasAnimatedItem: true, charging: true, env: env), P.Plan(fps: 15, step: 2), "şarjda dalga hızlanır")
        XCTAssertEqual(P.plan(mode: .light, hasAnimatedItem: true, charging: false, env: env), P.Plan(fps: 8, step: 1))
        XCTAssertNil(P.plan(mode: .off, hasAnimatedItem: true, charging: false, env: env))
        // Dolu (şarj bitti, takılı): plan charging=false ile de durmaz.
        XCTAssertNotNil(P.plan(mode: .live, hasAnimatedItem: true, charging: state(100, plugged: true, full: true).isCharging, env: env), "dolu: animasyon sürer")
        XCTAssertNil(P.plan(mode: .live, hasAnimatedItem: false, charging: false, env: env), "öğe menü çubuğunda değil")
        var e = env; e.visible = false
        XCTAssertNil(P.plan(mode: .live, hasAnimatedItem: true, charging: false, env: e), "görünmezken dur")
        e = env; e.screensAsleep = true
        XCTAssertNil(P.plan(mode: .live, hasAnimatedItem: true, charging: false, env: e), "ekran uykuda")
        e = env; e.sessionActive = false
        XCTAssertNil(P.plan(mode: .live, hasAnimatedItem: true, charging: false, env: e), "kilitli")
        e = env; e.reduceMotion = true
        XCTAssertNil(P.plan(mode: .live, hasAnimatedItem: true, charging: false, env: e), "Hareketi Azalt → statik")
        XCTAssertFalse(P.motionAllowed(.live, reduceMotion: true, lowPower: false))
        e = env; e.lowPower = true
        XCTAssertEqual(P.plan(mode: .live, hasAnimatedItem: true, charging: true, env: e), P.Plan(fps: 4, step: 1), "Düşük Güç: yavaş")
        XCTAssertNil(P.plan(mode: .light, hasAnimatedItem: true, charging: false, env: e), "Düşük Güç + Hafif: dur")
        XCTAssertTrue(P.motionAllowed(.live, reduceMotion: false, lowPower: true))
        XCTAssertFalse(P.motionAllowed(.off, reduceMotion: false, lowPower: false))
    }

    @MainActor
    func testAnimatorCachesAndClears() {
        let animator = BatteryLiquidAnimator()
        let key = BatteryFrameKey(state: state(78), options: .init(), appearance: .darkAqua, scale: 2)
        let base = NSImage(size: NSSize(width: 60, height: 22))
        base.addRepresentation(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 44, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0)!)
        let target = BatteryLiquidAnimator.Target(itemKey: "a", button: nil, base: base,
                                                  rect: CGRect(x: 2, y: 2, width: 39.5, height: 18), frameKey: key)
        let image = animator.show(target)
        XCTAssertEqual(image.size, base.size)
        XCTAssertEqual(animator.cachedFrameCount, BatteryGlyph.frameCount, "kareler bir kez önceden çizilir")
        XCTAssertFalse(animator.isRunning, "pencere yok (görünmüyor) → timer yok")
        XCTAssertNil(animator.plan)
        XCTAssertTrue(animator.currentFrame() === animator.currentFrame(), "aynı kare önbellekten atanır (yeniden çizim yok)")
        animator.clear()
        XCTAssertEqual(animator.cachedFrameCount, 0, "öğe kaldırılınca önbellek boşalır")
        XCTAssertNil(animator.target)
    }

    /// Görünürken timer başlar ve düğmenin görüntüsü kare kare değişir; görünmez olunca durur.
    @MainActor
    func testAnimatorDrivesButtonFrameByFrame() {
        let animator = BatteryLiquidAnimator()
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 50, height: 22))
        var values = WidgetValues.sample
        values.battery = state(64, charging: true)
        let mac = MenuBarComponent(.batteryLevel, visual: .batteryCapsule)
        let config = MenuBarConfig(components: [mac])
        let appearance = NSAppearance(named: .darkAqua)!
        let base = MenuBarComposer.bitmap(MenuBarComposer.image(for: [mac], config: config, values: values, battery: .hidden),
                                          appearance: appearance, scale: 2)
        let rect = MenuBarComposer.animatedBatteryRect(in: [mac], config: config, values: values)!
        animator.visibilityOverride = true
        let first = animator.show(.init(itemKey: "bat", button: button, base: base, rect: rect,
                                        frameKey: BatteryFrameKey(state: values.battery!, options: mac.battery,
                                                                  appearance: .darkAqua, scale: 2), appearance: appearance))
        button.image = first
        XCTAssertTrue(animator.isRunning)
        XCTAssertEqual(animator.plan, BatteryAnimationPolicy.Plan(fps: 15, step: 2))
        XCTAssertTrue(first === base, "düğme görüntüsü gövdesiz taban; sıvı katmanda")
        func contentsID() -> ObjectIdentifier? { button.layer?.sublayers?.last?.contents.map { ObjectIdentifier($0 as AnyObject) } }
        var seen: [ObjectIdentifier] = contentsID().map { [$0] } ?? []
        XCTAssertFalse(seen.isEmpty, "katman içeriği atanmış")
        let deadline = Date().addingTimeInterval(1.3)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            if let id = contentsID(), id != seen.last { seen.append(id) }
        }
        XCTAssertGreaterThanOrEqual(seen.count, 4, "katman içeriği kare kare değişir (\(seen.count))")
        XCTAssertTrue(button.image === first || button.image == nil, "tikte button.image atanmaz")
        animator.visibilityOverride = false
        XCTAssertFalse(animator.isRunning, "görünmezken durur")
        animator.clear()
    }

    // MARK: Maliyet ölçümü

    /// Tik başına maliyet: önceden çizilmiş kare bindirme vs. her karede tam çizim (karşılaştırma için).
    func testFrameCostMeasurement() {
        var values = WidgetValues.sample
        values.battery = state(78)
        let mac = MenuBarComponent(.batteryLevel, visual: .batteryCapsule)
        let combined = MenuBarConfig.default.enabledComponents + [mac]
        let config = MenuBarConfig(components: combined)
        let appearance = NSAppearance(named: .darkAqua)!
        let key = BatteryFrameKey(state: values.battery!, options: mac.battery, appearance: .darkAqua, scale: 2)
        let clock = ContinuousClock()
        func micros(_ runs: Int, _ body: () -> Void) -> Double {
            body() // ısınma
            let d = clock.measure { for _ in 0..<runs { body() } }
            return Double(d.components.attoseconds) / 1e12 / Double(runs) + Double(d.components.seconds) * 1e6 / Double(runs)
        }
        let frames = micros(5) { _ = BatteryFrameRenderer.frames(key, appearance: appearance) }
        let soloBase = MenuBarComposer.bitmap(MenuBarComposer.image(for: [mac], config: MenuBarConfig(components: [mac]), values: values,
                                                                    battery: .hidden), appearance: appearance, scale: 2)
        let soloRect = MenuBarComposer.animatedBatteryRect(in: [mac], config: MenuBarConfig(components: [mac]), values: values)!
        let base = MenuBarComposer.bitmap(MenuBarComposer.image(for: combined, config: config, values: values, battery: .hidden),
                                          appearance: appearance, scale: 2)
        let rect = MenuBarComposer.animatedBatteryRect(in: combined, config: config, values: values)!
        let frame = BatteryFrameRenderer.frame(key, appearance: appearance, index: 3)
        let soloComposite = micros(200) { _ = MenuBarComposer.composite(base: soloBase, overlay: frame, at: soloRect) }
        let composite = micros(200) { _ = MenuBarComposer.composite(base: base, overlay: frame, at: rect) }
        let fullRedraw = micros(50) {
            _ = MenuBarComposer.bitmap(MenuBarComposer.image(for: combined, config: config, values: values,
                                                             battery: .wave(phase: 0.3, amplitude: 1)), appearance: appearance, scale: 2)
        }
        print(String(format: "BATTERY_COST: 24 kare üretimi %.0f µs | tik (yalnız pil, önbelleğe girmeden önce) %.1f µs | "
                     + "tik (birleşik çubuk) %.1f µs | karşılaştırma: her karede tam çizim %.1f µs | 12 fps birleşik ≈ %%%.3f çekirdek",
                     frames, soloComposite, composite, fullRedraw, composite * 12 / 1e6 * 100))
        XCTAssertLessThan(composite, fullRedraw, "bindirme tam çizimden ucuz")
    }

    // MARK: Animasyon stilleri

    /// İki karenin bayt başına ortalama mutlak farkı (0…255).
    private func diff(_ a: NSImage, _ b: NSImage) -> Double {
        guard let ra = a.representations.first as? NSBitmapImageRep, let rb = b.representations.first as? NSBitmapImageRep,
              ra.pixelsWide == rb.pixelsWide, ra.pixelsHigh == rb.pixelsHigh,
              let pa = ra.bitmapData, let pb = rb.bitmapData else { return .infinity }
        let n = ra.bytesPerRow * ra.pixelsHigh
        var sum = 0
        for i in 0..<n { sum += abs(Int(pa[i]) - Int(pb[i])) }
        return Double(sum) / Double(n)
    }

    func testStylesDeterministicMovingSeamless() {
        XCTAssertEqual(BatteryGlyphOptions.Style.allCases.count, 10)
        XCTAssertEqual(BatteryGlyphOptions.Style.allCases.map(\.displayName),
                       ["Sıvı", "Huzme", "Kabarcıklar", "Şeritler", "Nefes", "Aurora", "Okyanus", "Segmentler", "Kıvılcım", "Nabız"])
        let n = BatteryGlyph.frameCount
        XCTAssertTrue((24...30).contains(n))
        for style in BatteryGlyphOptions.Style.allCases {
            for s in [state(78), state(100), state(64, charging: true)] {
                let key = BatteryFrameKey(state: s, options: .init(style: style), appearance: .darkAqua, scale: 2)
                let frames = BatteryFrameRenderer.frames(key)
                XCTAssertEqual(frames.count, n)
                XCTAssertEqual(diff(BatteryFrameRenderer.frame(key, index: 7), BatteryFrameRenderer.frame(key, index: 7)), 0,
                               "\(style) deterministik")
                XCTAssertGreaterThan(diff(frames[0], frames[n / 2]), 0.05, "\(style) %\(s.level): hareket var")
                let adjacent = (0..<(n - 1)).map { diff(frames[$0], frames[$0 + 1]) }
                let seam = diff(frames[n - 1], frames[0])
                XCTAssertLessThanOrEqual(seam, (adjacent.max() ?? 0) * 1.2 + 0.02, "\(style) %\(s.level): döngü dikişsiz")
            }
        }
    }

    func testStylesAtLevels() {
        for style in BatteryGlyphOptions.Style.allCases {
            for level in [0, 1, 20, 50, 100] {
                let key = BatteryFrameKey(state: state(level), options: .init(style: style, fillColor: BatteryGlyphOptions.Swatch.blue.color),
                                          appearance: .aqua, scale: 2)
                XCTAssertNotNil(BatteryFrameRenderer.frame(key, index: 4).tiffRepresentation, "\(style) %\(level)")
            }
            let dead = BatteryFrameKey(state: state(0, charging: true), options: .init(style: style), appearance: .darkAqua, scale: 2)
            XCTAssertEqual(diff(BatteryFrameRenderer.frame(dead, index: 0), BatteryFrameRenderer.frame(dead, index: 15)), 0,
                           "\(style) %0: dolgu yok, süs yok")
            // Kapalı: stil süsü yok, tüm kareler aynı.
            let off = BatteryFrameKey(state: state(64), options: .init(motion: .off, style: style), appearance: .darkAqua, scale: 2)
            XCTAssertEqual(diff(BatteryFrameRenderer.frame(off, index: 0), BatteryFrameRenderer.frame(off, index: 15)), 0)
        }
    }

    func testStyleAndColorKeys() {
        let blue = BatteryGlyphOptions.Swatch.blue.color
        let base = BatteryFrameKey(state: state(78), options: .init(), appearance: .darkAqua, scale: 2)
        XCTAssertEqual(base, BatteryFrameKey(state: state(78), options: .init(style: .liquid, fillColor: nil), appearance: .darkAqua, scale: 2))
        XCTAssertNotEqual(base, BatteryFrameKey(state: state(78), options: .init(style: .beam), appearance: .darkAqua, scale: 2))
        let colored = BatteryFrameKey(state: state(78), options: .init(fillColor: blue), appearance: .darkAqua, scale: 2)
        XCTAssertNotEqual(base, colored)
        XCTAssertEqual(colored, BatteryFrameKey(state: state(78), options: .init(fillColor: blue), appearance: .darkAqua, scale: 2))
        XCTAssertNotEqual(colored, BatteryFrameKey(state: state(78), options: .init(fillColor: blue, secondColor: blue),
                                                   appearance: .darkAqua, scale: 2))
        XCTAssertEqual(colored.options.fillColor, blue, "anahtardan geri kurulan seçenekler rengi taşır")
        XCTAssertEqual(BatteryFrameKey(state: state(78), options: .init(style: .aurora), appearance: .darkAqua, scale: 2).options.style, .aurora)
        XCTAssertGreaterThan(diff(BatteryFrameRenderer.frame(base, index: 3), BatteryFrameRenderer.frame(colored, index: 3)), 0.5,
                             "renk pikselleri değiştirir")
        // Hazır renkler ayrı.
        XCTAssertEqual(Set(BatteryGlyphOptions.Swatch.allCases.map(\.color)).count, 8)
    }

    func testCustomColorSafetyAlert() {
        XCTAssertTrue(BatteryGlyph.customAlert(state(10)))
        XCTAssertTrue(BatteryGlyph.customAlert(state(3)))
        XCTAssertFalse(BatteryGlyph.customAlert(state(11)))
        XCTAssertFalse(BatteryGlyph.customAlert(state(5, charging: true)))
        XCTAssertFalse(BatteryGlyph.customAlert(state(5, plugged: true)))
        // Özel renkte %8: kırmızı nabız (stil Nefes değilken de kareler değişir), %50'de kırmızı yok.
        let pink = BatteryGlyphOptions.Swatch.blue.color
        let low = BatteryFrameKey(state: state(8), options: .init(statusColors: false, style: .stripes, fillColor: pink),
                                  appearance: .darkAqua, scale: 2)
        let mid = BatteryFrameKey(state: state(50), options: .init(statusColors: false, style: .stripes, fillColor: pink),
                                  appearance: .darkAqua, scale: 2)
        func redness(_ image: NSImage) -> Double {
            guard let rep = image.representations.first as? NSBitmapImageRep else { return 0 }
            var total = 0.0
            for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) { total += max(0, c.redComponent - c.blueComponent) * c.alphaComponent }
            } }
            return total
        }
        XCTAssertGreaterThan(redness(BatteryFrameRenderer.frame(low, index: 0)), redness(BatteryFrameRenderer.frame(mid, index: 0)) + 5)
    }

    func testStyleOptionsCodable() throws {
        let legacy = try JSONDecoder().decode(BatteryGlyphOptions.self, from: Data(#"{"animation":"light","size":"small"}"#.utf8))
        XCTAssertEqual(legacy.style, .liquid, "eski ayar: Sıvı")
        XCTAssertNil(legacy.fillColor, "eski ayar: otomatik renk")
        XCTAssertNil(legacy.secondColor)
        let bogus = try JSONDecoder().decode(BatteryGlyphOptions.self, from: Data(#"{"style":"laser","fillColor":"x"}"#.utf8))
        XCTAssertEqual(bogus.style, .liquid)
        XCTAssertNil(bogus.fillColor)
        let full = BatteryGlyphOptions(style: .aurora, fillColor: BatteryGlyphOptions.Swatch.pink.color,
                                       secondColor: RGBAColor(red: 0.1, green: 0.2, blue: 0.9))
        let data = try JSONEncoder().encode(full)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""style":"aurora""#))
        XCTAssertEqual(try JSONDecoder().decode(BatteryGlyphOptions.self, from: data), full)
        let plain = try JSONEncoder().encode(BatteryGlyphOptions())
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("fillColor"), "otomatik renk JSON'a yazılmaz")
    }

    func testCardRoundTripKeepsStyleAndColors() throws {
        var cards = MetricCardConfig.defaults
        let index = try XCTUnwrap(cards.firstIndex { $0.kind == .battery })
        cards[index].shown = true
        cards[index].batteryStyle = .ocean
        cards[index].batteryFill = BatteryGlyphOptions.Swatch.teal.color
        cards[index].batterySecond = RGBAColor(red: 0.2, green: 0.3, blue: 0.9)
        let components = cards.flatMap { $0.components() }
        let capsule = try XCTUnwrap(components.first { $0.visual == .batteryCapsule })
        XCTAssertEqual(capsule.battery.style, .ocean)
        XCTAssertEqual(capsule.battery.fillColor, BatteryGlyphOptions.Swatch.teal.color)
        let back = try XCTUnwrap(MetricCardConfig.cards(from: components), "stil/renk seçimi basit düzenleyiciyi bozmaz")
        let card = try XCTUnwrap(back.first { $0.kind == .battery })
        XCTAssertEqual(card.batteryStyle, .ocean)
        XCTAssertEqual(card.batteryFill, BatteryGlyphOptions.Swatch.teal.color)
        XCTAssertEqual(card.batterySecond, RGBAColor(red: 0.2, green: 0.3, blue: 0.9))
    }

    /// 10 stil x (%25, %78, %100, şarj) x faz 0 / 0.5 (koyu, açık) + özel renk sütunu.
    func testExportStyleContactSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !dir.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; stil kontakt sayfası atlandı")
        }
        let states: [(String, BatteryGlyphState)] = [("%25", state(25)), ("%78", state(78)), ("%100", state(100)),
                                                      ("Şarj %64", state(64, charging: true))]
        let dark = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
        let light = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
        let pink = BatteryGlyphOptions.Swatch.pink.color, blue = BatteryGlyphOptions.Swatch.blue.color
        let columns: [(String, NSAppearance.Name, Double, NSColor, RGBAColor?, RGBAColor?)] = [
            ("koyu faz 0", .darkAqua, 0, dark, nil, nil), ("koyu faz 0.5", .darkAqua, 0.5, dark, nil, nil),
            ("açık faz 0", .aqua, 0, light, nil, nil), ("açık faz 0.5", .aqua, 0.5, light, nil, nil),
            ("koyu pembe/mavi 0.3", .darkAqua, 0.3, dark, pink, blue), ("açık mavi 0.3", .aqua, 0.3, light, blue, nil),
        ]
        let zoom: CGFloat = 4
        let labelW: CGFloat = 190, cellW: CGFloat = 175, rowH: CGFloat = 14 * zoom + 14, headerH: CGFloat = 30
        let rows = BatteryGlyphOptions.Style.allCases.flatMap { style in states.map { (style, $0.0, $0.1) } }
        let size = NSSize(width: labelW + cellW * CGFloat(columns.count), height: headerH + rowH * CGFloat(rows.count))
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.3, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white]
        for (ci, col) in columns.enumerated() {
            (col.0 as NSString).draw(at: NSPoint(x: labelW + CGFloat(ci) * cellW + 8, y: size.height - headerH + 6), withAttributes: attrs)
        }
        for (ri, row) in rows.enumerated() {
            let y = size.height - headerH - rowH * CGFloat(ri + 1)
            if ri % states.count == 0 {
                NSColor(white: 0.5, alpha: 1).setFill()
                NSRect(x: 0, y: y + rowH - 1, width: size.width, height: 1).fill()
            }
            ("\(row.0.displayName) · \(row.1)" as NSString).draw(at: NSPoint(x: 10, y: y + rowH / 2 - 9), withAttributes: attrs)
            for (ci, col) in columns.enumerated() {
                let cell = NSRect(x: labelW + CGFloat(ci) * cellW + 4, y: y + 4, width: cellW - 8, height: rowH - 8)
                col.3.setFill()
                NSBezierPath(roundedRect: cell, xRadius: 6, yRadius: 6).fill()
                let options = BatteryGlyphOptions(style: row.0, fillColor: col.4, secondColor: col.5)
                let key = BatteryFrameKey(state: row.2, options: options, appearance: col.1, scale: zoom)
                let image = BatteryFrameRenderer.frame(key, phase: col.2)
                let target = NSRect(x: cell.minX + 12, y: cell.midY - image.size.height * zoom / 2,
                                    width: image.size.width * zoom, height: image.size.height * zoom)
                image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let url = URL(filePath: dir).appending(path: "battery-styles-contact-sheet.png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("BATTERY_STYLES_SHEET: \(url.path())")
    }

    // MARK: Önizleme kontakt sayfası

    func testExportLiquidContactSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !dir.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; kontakt sayfası atlandı")
        }
        let rows: [(String, BatteryGlyphState, BatteryGlyphOptions)] = [
            ("%5", state(5), .init()),
            ("%20", state(20), .init()),
            ("%50", state(50), .init()),
            ("%78", state(78), .init()),
            ("%100", state(100), .init()),
            ("Şarj %64", state(64, charging: true), .init(showTime: true)),
            ("Dolu", state(100, plugged: true, full: true), .init()),
            ("Şarj %100", state(100, charging: true), .init()),
            ("Şarj %8", state(8, charging: true), .init()),
            ("Düşük güç %60", state(60, lowPower: true), .init()),
            ("Renk kapalı %12", state(12), .init(statusColors: false)),
            ("Küçük %78", state(78), .init(size: .small)),
            ("Büyük şarj %31", state(31, charging: true), .init(size: .large)),
        ]
        let zoom: CGFloat = 4
        let columns: [(String, NSAppearance.Name, Double, NSColor)] = [
            ("koyu · faz 0", .darkAqua, 0, NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)),
            ("koyu · faz 0.5", .darkAqua, 0.5, NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)),
            ("açık · faz 0", .aqua, 0, NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)),
            ("açık · faz 0.5", .aqua, 0.5, NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)),
        ]
        let labelW: CGFloat = 150, cellW: CGFloat = 330, rowH = ComponentRenderer.height * zoom + 16, headerH: CGFloat = 30
        let size = NSSize(width: labelW + cellW * CGFloat(columns.count), height: headerH + rowH * CGFloat(rows.count))
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.3, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white]
        for (ci, col) in columns.enumerated() {
            (col.0 as NSString).draw(at: NSPoint(x: labelW + CGFloat(ci) * cellW + 10, y: size.height - headerH + 6), withAttributes: labelAttrs)
        }
        for (ri, row) in rows.enumerated() {
            let y = size.height - headerH - rowH * CGFloat(ri + 1)
            (row.0 as NSString).draw(at: NSPoint(x: 10, y: y + rowH / 2 - 9), withAttributes: labelAttrs)
            var values = WidgetValues.sample
            values.battery = row.1
            let component = MenuBarComponent(.batteryLevel, visual: .batteryCapsule, battery: row.2)
            let config = MenuBarConfig(components: [component])
            for (ci, col) in columns.enumerated() {
                let cell = NSRect(x: labelW + CGFloat(ci) * cellW + 4, y: y + 4, width: cellW - 8, height: rowH - 8)
                col.3.setFill()
                NSBezierPath(roundedRect: cell, xRadius: 6, yRadius: 6).fill()
                let image = MenuBarComposer.image(for: [component], config: config, values: values, appearance: col.1, zoom: zoom,
                                                  battery: .wave(phase: col.2, amplitude: BatteryGlyph.amplitude(.live)))
                image.draw(at: NSPoint(x: cell.minX + 12, y: cell.midY - image.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let url = URL(filePath: dir).appending(path: "battery-liquid-contact-sheet.png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("BATTERY_SHEET: \(url.path())")

        // İsteğe bağlı: referans menü çubuğu görüntüsüyle (2x) aynı ölçekte yan yana.
        if let refPath = ProcessInfo.processInfo.environment["ADALMON_REFERENCE_PNG"], let ref = NSImage(contentsOfFile: refPath),
           let refRep = ref.representations.first {
            let refSize = NSSize(width: refRep.pixelsWide, height: refRep.pixelsHigh) // 2x piksel = 1:1 çiz
            var values = WidgetValues.sample
            values.battery = state(100)
            let comps = [MenuBarComponent(.batteryLevel, visual: .batteryCapsule)]
            let ours = MenuBarComposer.image(for: comps, config: MenuBarConfig(components: comps), values: values,
                                             appearance: .darkAqua, zoom: 2)
            let out = NSSize(width: max(refSize.width, ours.size.width + 40), height: refSize.height + ours.size.height + 20)
            let cmp = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(out.width), pixelsHigh: Int(out.height),
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: cmp)
            NSColor(srgbRed: 0.33, green: 0.4, blue: 0.6, alpha: 1).setFill()
            NSRect(origin: .zero, size: out).fill()
            ref.draw(in: NSRect(x: 0, y: out.height - refSize.height, width: refSize.width, height: refSize.height))
            ours.draw(at: NSPoint(x: 28, y: 10), from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            let cmpURL = URL(filePath: dir).appending(path: "battery-vs-reference.png")
            try XCTUnwrap(cmp.representation(using: .png, properties: [:])).write(to: cmpURL)
            print("BATTERY_COMPARE: \(cmpURL.path())")
        }
    }
}
