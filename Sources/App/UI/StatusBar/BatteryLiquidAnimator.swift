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
        // Tik yalnızca önceden çizilmiş kareyi katmana atar (ölçümde CPU'nun asıl yükü değil) → akıcı fps;
        // şarjda hız fps yerine faz adımıyla artar.
        if env.lowPower { return Plan(fps: 4, step: 1) } // yalnızca Canlı buraya gelir: yavaş ve sakin
        switch mode {
        case .off: return nil
        case .light: return Plan(fps: 8, step: step)
        case .live: return Plan(fps: 15, step: step)
        }
    }
}

/// Önceden çizilmiş pil gövdesi karelerinin anahtarı: seviye + durum + boyut + renk + stil + görünüm + ölçek.
struct BatteryFrameKey: Hashable, Sendable {
    var state: BatteryGlyphState
    var size: BatteryGlyphOptions.Size
    var statusColors: Bool
    var animation: BatteryGlyphOptions.Animation
    var style: BatteryGlyphOptions.Style
    var fillColor: RGBAColor?
    var secondColor: RGBAColor?
    var appearance: String
    var scale: CGFloat

    init(state: BatteryGlyphState, options: BatteryGlyphOptions, appearance: NSAppearance.Name, scale: CGFloat) {
        var s = state
        s.timeText = nil // süre gövdenin dışında çizilir; kareleri etkilemez
        s.chargeTier = nil // şimşek de gövdenin dışında (taban görüntüde); güç kademesi kareleri yeniden üretmez
        self.state = s
        size = options.size
        statusColors = options.statusColors
        animation = options.motion
        style = options.style
        fillColor = options.fillColor
        secondColor = options.secondColor
        self.appearance = appearance.rawValue
        self.scale = scale
    }

    var options: BatteryGlyphOptions {
        BatteryGlyphOptions(statusColors: statusColors, size: size, motion: animation, style: style,
                            fillColor: fillColor, secondColor: secondColor)
    }
}

enum BatteryFrameRenderer {
    static func phase(_ index: Int) -> Double { Double(index % BatteryGlyph.frameCount) / Double(BatteryGlyph.frameCount) }

    /// Tek gövde karesi (bitmap). `level` kesirli olabilir (seviye geçişi).
    /// `appearance`: düğmenin gerçek `effectiveAppearance`'ı (Yüksek Karşıtlık vb. adla yeniden kurulamayabilir).
    static func frame(_ key: BatteryFrameKey, appearance: NSAppearance? = nil, level: Double? = nil, index: Int) -> NSImage {
        frame(key, appearance: appearance, level: level, phase: phase(index))
    }

    /// Belirli bir fazda tek kare (ayar önizlemesi için de kullanılır).
    static func frame(_ key: BatteryFrameKey, appearance: NSAppearance? = nil, level: Double? = nil, phase: Double) -> NSImage {
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
                                     wave: amplitude > 0 ? (phase, amplitude) : nil)
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

/// Şimşeğin sabit görüntüsü (bir kez çizilir; "nefes" Core Animation'da, uygulama CPU'su harcamaz).
enum BoltRenderer {
    /// Yuvarlak birleşimler ve ölçek büyümesi kesilmesin diye şimşek dikdörtgeninin çevresindeki pay (pt).
    static let pad: CGFloat = 1

    /// Şimşek dikdörtgeni + pay (bileşik görüntü koordinatlarında).
    static func frame(capsule: CGRect, size: BatteryGlyphOptions.Size) -> CGRect {
        BatteryGlyph.boltRect(size, capsule: capsule).insetBy(dx: -pad, dy: -pad)
    }

    static func image(_ state: BatteryGlyphState, statusColors: Bool, size: BatteryGlyphOptions.Size,
                      appearance: NSAppearance, scale: CGFloat) -> NSImage {
        let s = BatteryGlyph.boltSize(BatteryGlyph.metrics(size))
        let imageSize = CGSize(width: s.width + 2 * pad, height: s.height + 2 * pad)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(imageSize.width * scale)),
                                         pixelsHigh: Int(ceil(imageSize.height * scale)), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return NSImage(size: imageSize) }
        rep.size = imageSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            BatteryGlyph.boltColor(statusColors: statusColors, state).setFill()
            BatteryGlyph.boltPath(in: CGRect(origin: CGPoint(x: pad, y: pad), size: s)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: imageSize)
        image.addRepresentation(rep)
        return image
    }
}

/// Mac pili menü çubuğu öğesinin canlı sıvı animasyonu. Tikte çizim yok: önceden hazırlanmış gövde karesi, bir kez
/// çizilmiş "gövdesiz" taban görüntünün üstüne bindirilir ve sonuç önbelleğe alınır → döngü tamamlanınca yalnızca
/// `button.image` ataması kalır. Görünmezken, ekran uykudayken, oturum kilitliyken ya da Hareketi Azalt açıkken durur.
/// Şimşek ayrı bir katmandır (sabit görüntü); "nefesi" CABasicAnimation/CAKeyframeAnimation ile render sunucusunda döner
/// (uygulama tarafında çizim/timer yok); animasyon durunca (görünmez, uyku, kilit, Düşük Güç, kaldırma) katmandan silinir.
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
        /// Şimşeği olan tam pil durumu (güç kademesi dahil); `nil` → şimşek yok. Şimşek tabanda değil, ayrı katmandadır.
        var bolt: BatteryGlyphState? = nil
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
    /// Şimşek katmanı (sabit görüntü + Core Animation nefesi); şimşek yoksa `nil`.
    private(set) var boltLayer: CALayer?
    private var boltImage: (key: BoltImageKey, image: NSImage)?
    /// Katmanda şu an çalışan nefes (`nil` → statik).
    private(set) var boltAnimation: BatteryGlyph.BoltAnimation?
    /// Düğmesiz (test) yolda şimşeği de içeren taban.
    private var staticBase: NSImage?
    private var frameIndex = 0
    private var timer: Timer?
    private(set) var plan: BatteryAnimationPolicy.Plan?
    private var env = BatteryAnimationPolicy.Environment()
    private var transition: (from: Double, to: Double, start: TimeInterval)?
    private var displayedLevel: Double?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    static let transitionDuration: TimeInterval = 0.4

    private struct BoltImageKey: Equatable {
        var charging: Bool
        var plugged: Bool
        var tier: ChargeTier?
        var statusColors: Bool
        var size: BatteryGlyphOptions.Size
        var scale: CGFloat
        var appearance: String
    }

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
        staticBase = nil
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
        staticBase = nil
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
        installBolt(for: target, host: host)
        overlayBounds = .zero
        layoutOverlay()
    }

    private func removeOverlay() {
        overlay?.removeFromSuperlayer()
        overlay = nil
        overlayBounds = .zero
        removeBolt()
    }

    // MARK: Şimşek katmanı

    private func installBolt(for target: Target, host: CALayer) {
        guard let state = target.bolt, BatteryGlyph.showsBolt(state) else { removeBolt(); return }
        let layer: CALayer
        if let boltLayer, boltLayer.superlayer === host {
            layer = boltLayer
        } else {
            boltLayer?.removeAllAnimations()
            boltLayer?.removeFromSuperlayer()
            boltAnimation = nil
            layer = CALayer()
            layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
                             "opacity": NSNull(), "transform": NSNull()]
            layer.contentsGravity = .resize
            layer.isOpaque = false
            host.addSublayer(layer)
            boltLayer = layer
        }
        let appearance = target.appearance ?? NSAppearance(named: .darkAqua)!
        let scale = target.frameKey.scale
        let key = BoltImageKey(charging: state.isCharging, plugged: state.isPluggedIn, tier: state.chargeTier,
                               statusColors: target.frameKey.statusColors, size: target.frameKey.size, scale: scale,
                               appearance: appearance.name.rawValue)
        if boltImage?.key != key {
            boltImage = (key, BoltRenderer.image(state, statusColors: key.statusColors, size: key.size,
                                                 appearance: appearance, scale: scale))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contentsScale = scale
        layer.contents = boltImage.flatMap { Self.cgImage($0.image) }
        CATransaction.commit()
        updateBoltAnimation()
    }

    private func removeBolt() {
        boltLayer?.removeAllAnimations()
        boltLayer?.removeFromSuperlayer()
        boltLayer = nil
        boltImage = nil
        boltAnimation = nil
    }

    /// Nefes yalnızca zamanlayıcı planı varsa (görünür, uyanık, kilitsiz, Hareketi Azalt kapalı) ve Düşük Güç kapalıyken çalışır;
    /// değişmediyse dokunulmaz (her `show`'da yeniden başlayıp takılmasın), değiştiyse kesintisiz yeniden kurulur.
    private func updateBoltAnimation() {
        guard let boltLayer, let state = target?.bolt, let frameKey = target?.frameKey else { return }
        let desired = plan != nil && !env.lowPower ? BatteryGlyph.boltAnimation(state, motion: frameKey.animation) : nil
        let running = !(boltLayer.animationKeys() ?? []).isEmpty
        guard desired != boltAnimation || running != (desired != nil) else { return }
        boltLayer.removeAllAnimations()
        boltAnimation = desired
        guard let desired else { return }
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        func breath(_ keyPath: String, rest: Float, peak: Float) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: keyPath)
            a.values = [rest, peak, rest]
            a.keyTimes = [0, 0.5, 1]
            a.timingFunctions = [ease, ease]
            a.duration = desired.duration
            a.repeatCount = .infinity
            return a
        }
        boltLayer.add(breath("opacity", rest: 1, peak: desired.minOpacity), forKey: "bolt.opacity")
        if desired.scales {
            boltLayer.add(breath("transform.scale", rest: 1, peak: Float(desired.maxScale)), forKey: "bolt.scale")
        }
    }

    /// Katmanı düğme içinde, görüntünün (ortalanmış) üstünde gövde dikdörtgenine yerleştirir; yalnızca düğme boyutu değişince.
    private func layoutOverlay() {
        guard overlay != nil, let target, let button = target.button, button.bounds != overlayBounds else { return }
        overlayBounds = button.bounds
        var origin = button.cell?.imageRect(forBounds: button.bounds).origin
        if origin == nil || button.cell?.imageRect(forBounds: button.bounds).size == .zero {
            origin = CGPoint(x: (button.bounds.width - target.base.size.width) / 2, y: (button.bounds.height - target.base.size.height) / 2)
        }
        let o = origin ?? .zero
        /// Bileşik görüntü koordinatındaki (altta başlayan) dikdörtgeni düğme katmanı koordinatına çevirir.
        func layerFrame(_ r: CGRect) -> CGRect {
            let y = button.isFlipped ? o.y + target.base.size.height - r.maxY : o.y + r.minY
            return CGRect(x: o.x + r.minX, y: y, width: r.width, height: r.height)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay?.frame = layerFrame(target.rect)
        boltLayer?.frame = layerFrame(BoltRenderer.frame(capsule: target.rect, size: target.frameKey.size))
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

    /// Düğmesiz (test) yolda şimşek tabana elle bindirilir; düğmeli yolda taban şimşeksizdir (şimşek katmanda).
    private func baseImage(_ target: Target) -> NSImage {
        guard target.button == nil, let state = target.bolt, BatteryGlyph.showsBolt(state) else { return target.base }
        if let staticBase { return staticBase }
        let appearance = target.appearance ?? NSAppearance(named: .darkAqua)!
        let bolt = BoltRenderer.image(state, statusColors: target.frameKey.statusColors, size: target.frameKey.size,
                                      appearance: appearance, scale: target.frameKey.scale)
        let image = MenuBarComposer.composite(base: target.base, overlay: bolt,
                                              at: BoltRenderer.frame(capsule: target.rect, size: target.frameKey.size))
        staticBase = image
        return image
    }

    private func currentImage() -> NSImage {
        guard let target, let frames else { return NSImage() }
        let base = baseImage(target)
        if let transition {
            let p = min(1, (ProcessInfo.processInfo.systemUptime - transition.start) / Self.transitionDuration)
            let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
            let level = transition.from + (transition.to - transition.from) * eased
            displayedLevel = level
            if p >= 1 { self.transition = nil }
            // Geçiş kareleri tek seferlik; önbelleğe girmez.
            let capsule = BatteryFrameRenderer.frame(target.frameKey, appearance: target.appearance, level: level, index: frameIndex)
            return MenuBarComposer.composite(base: base, overlay: capsule, at: target.rect)
        }
        if let cached = composites[frameIndex] { return cached }
        let image = MenuBarComposer.composite(base: base, overlay: frames.images[frameIndex], at: target.rect)
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
        defer { updateBoltAnimation() }
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
