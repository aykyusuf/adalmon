import AppKit

/// Canlı sıvı animasyonunun başlat / durdur / hız kararı (saf; test edilir).
enum BatteryAnimationPolicy {
    struct Environment: Equatable, Sendable {
        var reduceMotion = false
        var lowPower = false
        /// Öğe penceresi görünür (occlusion), ekran uyanık, oturum etkin (kilitli değil).
        var visible = true
        var screensAsleep = false
        var sessionActive = true
    }

    struct Plan: Equatable, Sendable {
        /// Saniyedeki kare (timer aralığı 1/fps).
        var fps: Double
        /// Her tikte ilerlenen kare sayısı (şarjda 2 → dalga iki kat hızlı).
        var step: Int
    }

    /// Hareket hiç gösterilebilir mi (görünürlükten bağımsız): Kapalı, Hareketi Azalt ya da Düşük Güç + Hafif → statik.
    static func motionAllowed(_ mode: BatteryGlyphOptions.Animation, reduceMotion: Bool, lowPower: Bool) -> Bool {
        switch mode {
        case .off: false
        case .light: !reduceMotion && !lowPower
        case .live: !reduceMotion
        }
    }

    /// `nil` → timer durur.
    static func plan(mode: BatteryGlyphOptions.Animation, hasAnimatedItem: Bool, charging: Bool, env: Environment) -> Plan? {
        guard hasAnimatedItem, motionAllowed(mode, reduceMotion: env.reduceMotion, lowPower: env.lowPower),
              env.visible, !env.screensAsleep, env.sessionActive else { return nil }
        let step = charging ? 2 : 1
        // Kare başı maliyet yüksek ölçüldü: düşük fps; şarjda dalga hızı fps yerine faz adımıyla artar.
        if env.lowPower { return Plan(fps: 2, step: 1) } // yalnızca Canlı buraya gelir: yavaş ve sakin
        switch mode {
        case .off: return nil
        case .light: return Plan(fps: 4, step: step)
        case .live: return Plan(fps: 6, step: step)
        }
    }
}

/// Önceden çizilmiş pil gövdesi karelerinin anahtarı: seviye + durum + boyut + renk + görünüm + ölçek.
struct BatteryFrameKey: Hashable, Sendable {
    var state: BatteryGlyphState
    var size: BatteryGlyphOptions.Size
    var statusColors: Bool
    var animation: BatteryGlyphOptions.Animation
    var appearance: String
    var scale: CGFloat

    init(state: BatteryGlyphState, options: BatteryGlyphOptions, appearance: NSAppearance.Name, scale: CGFloat) {
        var s = state
        s.timeText = nil // süre gövdenin dışında çizilir; kareleri etkilemez
        self.state = s
        size = options.size
        statusColors = options.statusColors
        animation = options.motion
        self.appearance = appearance.rawValue
        self.scale = scale
    }

    var options: BatteryGlyphOptions {
        BatteryGlyphOptions(statusColors: statusColors, size: size, motion: animation)
    }
}

enum BatteryFrameRenderer {
    static func phase(_ index: Int) -> Double { Double(index % BatteryGlyph.frameCount) / Double(BatteryGlyph.frameCount) }

    /// Tek gövde karesi (bitmap). `level` kesirli olabilir (seviye geçişi).
    /// `appearance`: düğmenin gerçek `effectiveAppearance`'ı (Yüksek Karşıtlık vb. adla yeniden kurulamayabilir).
    static func frame(_ key: BatteryFrameKey, appearance: NSAppearance? = nil, level: Double? = nil, index: Int) -> NSImage {
        let m = BatteryGlyph.metrics(key.size)
        let size = BatteryGlyph.capsuleSize(m, key.state)
        let amplitude = BatteryGlyph.amplitude(key.animation)
        let appearance = appearance ?? NSAppearance(named: NSAppearance.Name(key.appearance)) ?? NSAppearance(named: .darkAqua)!
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * key.scale)),
                                         pixelsHigh: Int(ceil(size.height * key.scale)), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return NSImage(size: size) }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            BatteryGlyph.drawCapsule(key.state, options: key.options, level: level ?? Double(key.state.level),
                                     in: CGRect(origin: .zero, size: size),
                                     wave: amplitude > 0 ? (phase(index), amplitude) : nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// Bir dalga döngüsünün tüm kareleri (bir kez çizilir, sonra yalnızca atanır).
    static func frames(_ key: BatteryFrameKey, appearance: NSAppearance? = nil) -> [NSImage] {
        (0..<BatteryGlyph.frameCount).map { frame(key, appearance: appearance, index: $0) }
    }
}

/// Mac pili menü çubuğu öğesinin canlı sıvı animasyonu. Tikte çizim yok: önceden hazırlanmış gövde karesi, bir kez
/// çizilmiş "gövdesiz" taban görüntünün üstüne bindirilir ve sonuç önbelleğe alınır → döngü tamamlanınca yalnızca
/// `button.image` ataması kalır. Görünmezken, ekran uykudayken, oturum kilitliyken ya da Hareketi Azalt açıkken durur.
@MainActor
final class BatteryLiquidAnimator {
    struct Target {
        var itemKey: String
        weak var button: NSStatusBarButton?
        /// Pil gövdesi boş bırakılmış bileşik görüntü (bitmap).
        var base: NSImage
        var rect: CGRect
        var frameKey: BatteryFrameKey
        var appearance: NSAppearance? = nil
    }

    /// Hareket izni değişti (Hareketi Azalt / Düşük Güç): denetleyici statik ↔ canlı yeniden çizsin.
    var onMotionPolicyChange: (() -> Void)?

    private(set) var target: Target?
    private var frames: (key: BatteryFrameKey, images: [NSImage])?
    private var composites: [Int: NSImage] = [:]
    /// Katman yolu: gövde kareleri bir alt katmanın `contents`'ine yazılır (button.image ataması / NSStatusItem yeniden
    /// çizim yolu atlanır). Düğme yoksa (testler) eski bileşik görüntü yolu kullanılır.
    private var overlay: CALayer?
    private var overlayBounds: CGRect = .zero
    private var cgFrames: [Int: CGImage] = [:]
    private var frameIndex = 0
    private var timer: Timer?
    private(set) var plan: BatteryAnimationPolicy.Plan?
    private var env = BatteryAnimationPolicy.Environment()
    private var transition: (from: Double, to: Double, start: TimeInterval)?
    private var displayedLevel: Double?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    static let transitionDuration: TimeInterval = 0.4

    init() {
        env.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        env.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        observe()
    }

    var isRunning: Bool { timer != nil }
    /// Testler için: pencere görünürlüğünü (occlusion) zorla.
    var visibilityOverride: Bool? { didSet { reevaluate() } }
    var cachedFrameCount: Int { frames?.images.count ?? 0 }

    func motionAllowed(_ mode: BatteryGlyphOptions.Animation) -> Bool {
        BatteryAnimationPolicy.motionAllowed(mode, reduceMotion: env.reduceMotion, lowPower: env.lowPower)
    }

    /// Yeni içerik (render anahtarı değişti): kareleri gerekirse yeniden üret, şu anki kareyi döndür.
    func show(_ new: Target) -> NSImage {
        if frames?.key != new.frameKey {
            frames = (new.frameKey, BatteryFrameRenderer.frames(new.frameKey, appearance: new.appearance))
            cgFrames = [:]
        }
        composites = [:]
        let newLevel = Double(new.frameKey.state.level)
        if let old = target, old.itemKey == new.itemKey, timer != nil,
           let shown = displayedLevel, abs(shown - newLevel) >= 0.5 {
            transition = (shown, newLevel, ProcessInfo.processInfo.systemUptime)
        } else {
            transition = nil
            displayedLevel = newLevel
        }
        target = new
        reevaluate()
        if new.button != nil {
            // Düğmenin görüntüsü gövdesiz taban; sıvı gövde katmanda hareket eder.
            installOverlay(for: new)
            applyOverlay()
            return new.base
        }
        removeOverlay()
        return currentImage()
    }

    /// Öğe kaldırıldı ya da animasyon kapandı: timer ve tüm önbellek temizlenir.
    func clear() {
        stopTimer()
        removeOverlay()
        target = nil
        frames = nil
        composites = [:]
        cgFrames = [:]
        transition = nil
        displayedLevel = nil
        frameIndex = 0
    }

    // MARK: Kareler

    /// Şu anki kare (önbellekten; testler için).
    func currentFrame() -> NSImage { currentImage() }

    // MARK: Katman

    private func installOverlay(for target: Target) {
        guard let button = target.button else { return }
        button.wantsLayer = true
        guard let host = button.layer else { return }
        let layer: CALayer
        if let overlay, overlay.superlayer === host {
            layer = overlay
        } else {
            overlay?.removeFromSuperlayer()
            layer = CALayer()
            layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
            layer.contentsGravity = .resize
            layer.isOpaque = false
            host.addSublayer(layer)
            overlay = layer
        }
        layer.contentsScale = target.frameKey.scale
        overlayBounds = .zero
        layoutOverlay()
    }

    private func removeOverlay() {
        overlay?.removeFromSuperlayer()
        overlay = nil
        overlayBounds = .zero
    }

    /// Katmanı düğme içinde, görüntünün (ortalanmış) üstünde gövde dikdörtgenine yerleştirir; yalnızca düğme boyutu değişince.
    private func layoutOverlay() {
        guard let overlay, let target, let button = target.button, button.bounds != overlayBounds else { return }
        overlayBounds = button.bounds
        var origin = button.cell?.imageRect(forBounds: button.bounds).origin
        if origin == nil || button.cell?.imageRect(forBounds: button.bounds).size == .zero {
            origin = CGPoint(x: (button.bounds.width - target.base.size.width) / 2, y: (button.bounds.height - target.base.size.height) / 2)
        }
        let o = origin ?? .zero
        let y = button.isFlipped ? o.y + target.base.size.height - target.rect.maxY : o.y + target.rect.minY
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.frame = CGRect(x: o.x + target.rect.minX, y: y, width: target.rect.width, height: target.rect.height)
        CATransaction.commit()
    }

    private func applyOverlay() {
        guard let overlay, let target, let frames else { return }
        layoutOverlay()
        var cg: CGImage?
        if let transition {
            let p = min(1, (ProcessInfo.processInfo.systemUptime - transition.start) / Self.transitionDuration)
            let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
            let level = transition.from + (transition.to - transition.from) * eased
            displayedLevel = level
            if p >= 1 { self.transition = nil }
            cg = Self.cgImage(BatteryFrameRenderer.frame(target.frameKey, appearance: target.appearance, level: level, index: frameIndex))
        } else if let cached = cgFrames[frameIndex] {
            cg = cached
        } else {
            cg = Self.cgImage(frames.images[frameIndex])
            cgFrames[frameIndex] = cg
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.contents = cg
        CATransaction.commit()
    }

    private static func cgImage(_ image: NSImage) -> CGImage? {
        (image.representations.first as? NSBitmapImageRep)?.cgImage
    }

    private func currentImage() -> NSImage {
        guard let target, let frames else { return NSImage() }
        if let transition {
            let p = min(1, (ProcessInfo.processInfo.systemUptime - transition.start) / Self.transitionDuration)
            let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
            let level = transition.from + (transition.to - transition.from) * eased
            displayedLevel = level
            if p >= 1 { self.transition = nil }
            // Geçiş kareleri tek seferlik; önbelleğe girmez.
            let capsule = BatteryFrameRenderer.frame(target.frameKey, appearance: target.appearance, level: level, index: frameIndex)
            return MenuBarComposer.composite(base: target.base, overlay: capsule, at: target.rect)
        }
        if let cached = composites[frameIndex] { return cached }
        let image = MenuBarComposer.composite(base: target.base, overlay: frames.images[frameIndex], at: target.rect)
        composites[frameIndex] = image
        return image
    }

    private func tick() {
        guard let plan, target?.button != nil else { stopTimer(); return }
        frameIndex = (frameIndex + plan.step) % BatteryGlyph.frameCount
        if overlay != nil { applyOverlay(); return }
        let image = currentImage()
        if target?.button?.image !== image { target?.button?.image = image }
    }

    // MARK: Yaşam döngüsü

    private func reevaluate() {
        if let forced = visibilityOverride {
            env.visible = forced
        } else if let window = target?.button?.window {
            env.visible = window.occlusionState.contains(.visible)
        } else {
            env.visible = false
            if target != nil {
                // Öğe penceresi henüz yerleşmemiş olabilir; bir kez daha bak.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.target?.button?.window != nil else { return }
                        self.reevaluate()
                    }
                }
            }
        }
        let key = target?.frameKey
        let next = key.flatMap {
            BatteryAnimationPolicy.plan(mode: $0.animation, hasAnimatedItem: true, charging: $0.state.isCharging, env: env)
        }
        guard next != plan || (next != nil && timer == nil) else { return }
        plan = next
        stopTimer()
        guard let next else { transition = nil; return }
        let interval = 1 / next.fps
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = interval * 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        if target == nil { plan = nil }
    }

    private func observe() {
        let ws = NSWorkspace.shared.notificationCenter
        let dc = NotificationCenter.default
        // Gövdeye yalnızca nesne kimliği (Sendable) geçer.
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor (ObjectIdentifier?) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
                let sender = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated { body(sender) }
            }
            observers.append((center, token))
        }
        on(ws, NSWorkspace.screensDidSleepNotification) { [weak self] _ in self?.env.screensAsleep = true; self?.reevaluate() }
        on(ws, NSWorkspace.screensDidWakeNotification) { [weak self] _ in self?.env.screensAsleep = false; self?.reevaluate() }
        on(ws, NSWorkspace.sessionDidResignActiveNotification) { [weak self] _ in self?.env.sessionActive = false; self?.reevaluate() }
        on(ws, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] _ in self?.env.sessionActive = true; self?.reevaluate() }
        let locked = DistributedNotificationCenter.default()
        on(locked, Notification.Name("com.apple.screenIsLocked")) { [weak self] _ in self?.env.sessionActive = false; self?.reevaluate() }
        on(locked, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] _ in self?.env.sessionActive = true; self?.reevaluate() }
        on(dc, NSWindow.didChangeOcclusionStateNotification) { [weak self] sender in
            guard let self, let window = self.target?.button?.window, sender == ObjectIdentifier(window) else { return }
            self.reevaluate()
        }
        on(ws, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] _ in
            self?.motionInputsChanged(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                      lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
        on(dc, Notification.Name.NSProcessInfoPowerStateDidChange) { [weak self] _ in
            self?.motionInputsChanged(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                      lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
    }

    private func motionInputsChanged(reduceMotion: Bool, lowPower: Bool) {
        guard env.reduceMotion != reduceMotion || env.lowPower != lowPower else { return }
        env.reduceMotion = reduceMotion
        env.lowPower = lowPower
        reevaluate()
        onMotionPolicyChange?()
    }
}
