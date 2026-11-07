import AVFoundation

/// İki örnekli döngü: normalde TEK oynatıcı çalışır. Aralığın bitmesine `geçiş + 0,5 sn` kala sonraki klip
/// (aynı video ya da sıradaki öğe) gizli katmanda, kırpma başlangıcında HAZIRLANIR (`addBoundaryTimeObserver`,
/// yoklama yok); ilk kare hazır olunca opaklık geçişi (CABasicAnimation, ease-in-out) başlar ve bittiğinde eski
/// oynatıcı serbest bırakılır. Yalnızca hazırlık + geçiş sırasında iki çözücü vardır.
/// Geçiş süresi 0 ise (oynatma listesi, geçiş kapalı) aynı akış sert geçişle çalışır: sonraki klip önceden hazırdır.
@MainActor
final class CrossfadeBackend: LoopBackend {
    private let host: VideoHostLayer
    private let timing: LoopTiming
    private var clips: [LoopClip]
    private let reduceMotion: @MainActor () -> Bool
    private let onFirstFrame: @MainActor () -> Void

    private var current: LoopInstance?
    private var incoming: LoopInstance?
    private var incomingReady = false
    /// Dışarıdan istenen geçiş (duvar kâğıdı döngüsü): hazır olur olmaz, mevcut klibin sonunu beklemeden başlar.
    private var incomingForced = false
    private var nextOverride: LoopClip?
    private var currentEnded = false
    private var fading = false
    private var fadeSerial = 0
    private var fadeTask: Task<Void, Never>?
    private var paused: Bool
    private var stopped = false
    private var startDriver: LoopStartDriver?

    init(host: VideoHostLayer, timing: LoopTiming, clips: [LoopClip], paused: Bool,
         reduceMotion: @escaping @MainActor () -> Bool, onFirstFrame: @escaping @MainActor () -> Void) {
        self.host = host
        self.timing = timing
        self.clips = clips
        self.paused = paused
        self.reduceMotion = reduceMotion
        self.onFirstFrame = onFirstFrame
    }

    // MARK: Başlat / durdur

    func start() {
        guard let first = clips.first else { return }
        let instance = LoopInstance(clip: first, index: 0)
        current = instance
        attach(instance, opacity: 0)            // poster / sabit görüntü görünür kalır; ilk kare hazır olunca belirir
        let range = first.range
        let driver = LoopStartDriver(player: instance.player, asset: instance.asset, start: range.isTrimmed ? range.startTime : nil) { [weak self, weak instance] in
            guard let self, !self.stopped, let instance else { return }
            instance.layer.fadeIn()
            self.onFirstFrame()
        }
        driver.paused = paused
        startDriver = driver
        instance.readyObservation = instance.layer.observe(\.isReadyForDisplay, options: [.new]) { layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor [weak driver] in driver?.layerReady() }
        }
        arm(instance)
        driver.begin()
    }

    func stop() {
        stopped = true
        startDriver?.cancel()
        startDriver = nil
        fadeTask?.cancel()
        fadeTask = nil
        fadeSerial += 1
        current?.teardown()
        incoming?.teardown()
        current = nil
        incoming = nil
    }

    func setPaused(_ newValue: Bool) {
        guard newValue != paused, !stopped else { return }
        paused = newValue
        startDriver?.paused = newValue
        if newValue {
            // Geçişin ortasında duraklatma: geçişi anında tamamla (iki çözücü donuk kalmasın), sonra durdur.
            if fading { completeTransition() }
            current?.player.pause()
            incoming?.player.pause()
        } else {
            if !currentEnded, startDriver?.hasStartedPlaying ?? true { current?.player.play() }
            maybeBeginTransition()
        }
    }

    func reattach() {
        for instance in [current, incoming] {
            guard let instance else { continue }
            instance.layer.player = nil
            instance.layer.player = instance.player
        }
    }

    func transition(to clip: LoopClip) -> Bool {
        guard !stopped, !paused, current != nil else { return false }
        nextOverride = clip
        if fading { return true }          // geçiş bitince `completeTransition` sıradakini hazırlar
        if let incoming {
            incoming.teardown()
            self.incoming = nil
            incomingReady = false
            incomingForced = false
        }
        prepareNext()
        return true
    }

    // MARK: Zamanlama

    /// Örneğin sınır gözlemcisini ve "sona geldi" bildirimini kurar.
    private func arm(_ instance: LoopInstance) {
        let range = instance.clip.range
        // Hazırlık zamanı, hareketi-azalt'sız (uzun) geçişe göre hesaplanır: kısa geçiş yalnızca erken hazırlık demektir.
        let fade = timing.fade(in: range, reduceMotion: false)
        if let prepare = timing.prepareTime(in: range, fade: fade) {
            if prepare <= range.start + 0.01 {
                // Çok kısa klip: bekleyecek zaman yok; hemen hazırla (geçiş sert olur).
                Task { @MainActor [weak self, weak instance] in
                    guard let self, let instance, instance === self.current else { return }
                    self.prepareNext()
                }
            } else {
                let time = NSValue(time: CMTime(seconds: prepare, preferredTimescale: 600))
                instance.boundaryToken = instance.player.addBoundaryTimeObserver(forTimes: [time], queue: .main) { [weak self, weak instance] in
                    MainActor.assumeIsolated {
                        guard let self, let instance, instance === self.current else { return }
                        self.prepareNext()
                    }
                }
            }
        }
        // Yedek: uyku / takılma sonrası sınır atlanırsa aralık sonunda (forwardPlaybackEndTime) yine geçilir.
        instance.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: instance.item, queue: .main) { [weak self, weak instance] _ in
            MainActor.assumeIsolated {
                guard let self, let instance else { return }
                self.currentDidEnd(instance)
            }
        }
    }

    private func prepareNext() {
        guard !stopped, incoming == nil, !fading, let current else { return }
        let clip: LoopClip
        let index: Int
        if let override = nextOverride {
            clips = [override]
            clip = override
            index = 0
            nextOverride = nil
            incomingForced = true
        } else {
            index = LoopTiming.nextIndex(after: current.index, count: clips.count)
            clip = clips[index]
            incomingForced = false
        }
        let instance = LoopInstance(clip: clip, index: index)
        incoming = instance
        incomingReady = false
        attach(instance, opacity: 0)
        instance.seekToStart()
        instance.readyObservation = instance.layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self, weak instance] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor [weak self, weak instance] in
                guard let self, let instance else { return }
                self.incomingBecameReady(instance)
            }
        }
        instance.statusObservation = instance.item.observe(\.status, options: [.new]) { [weak self, weak instance] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self, weak instance] in
                guard let self, let instance else { return }
                self.incomingFailed(instance)
            }
        }
    }

    private func incomingBecameReady(_ instance: LoopInstance) {
        guard instance === incoming else { return }
        incomingReady = true
        maybeBeginTransition()
    }

    private func incomingFailed(_ instance: LoopInstance) {
        guard instance === incoming, !fading else { return }
        instance.teardown()
        incoming = nil
        incomingReady = false
        incomingForced = false
        // Mevcut klip sonda donmuşsa başa al; bir sonraki turda yeniden denenir.
        guard let current, currentEnded else { return }
        currentEnded = false
        current.seekToStart()
        if current.clip.range.start == 0 { current.player.seek(to: .zero) }
        if !paused { current.player.play() }
    }

    private func currentDidEnd(_ instance: LoopInstance) {
        guard instance === current, !stopped else { return }
        currentEnded = true
        if incoming == nil && !fading { prepareNext() } else { maybeBeginTransition() }
    }

    /// Gelen örnek hazırsa ve koşullar uygunsa geçişi başlatır (duraklatılmışken beklenir).
    private func maybeBeginTransition() {
        guard !stopped, !paused, !fading, incomingReady, incoming != nil, let current else { return }
        let fade = timing.fade(in: current.clip.range, reduceMotion: reduceMotion())
        // Geçiş varsa hazır olur olmaz; yoksa (sert geçiş) mevcut klibin sonunda ya da dışarıdan istenmişse hemen.
        guard fade > 0 || currentEnded || incomingForced else { return }
        beginTransition(fade: fade)
    }

    private func beginTransition(fade: Double) {
        guard let incoming else { return }
        fading = true
        fadeSerial += 1
        let token = fadeSerial
        incoming.readyObservation = nil
        incoming.player.automaticallyWaitsToMinimizeStalling = false
        incoming.player.play()
        arm(incoming)
        guard fade > 0 else {
            setOpacity(incoming.layer, 1)
            completeTransition()
            return
        }
        setOpacity(incoming.layer, 1)        // model değeri; görünür geçişi aşağıdaki animasyon yapar
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = fade
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        incoming.layer.add(animation, forKey: "crossfade")
        fadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(fade + 0.1))
            guard !Task.isCancelled, let self, self.fadeSerial == token else { return }
            self.completeTransition()
        }
    }

    /// Geçiş bitti (ya da duraklatma yüzünden anında bitirildi): eski örneği bırak, gelen örnek mevcut olur.
    private func completeTransition() {
        fadeTask?.cancel()
        fadeTask = nil
        fadeSerial += 1
        guard let incoming else { fading = false; return }
        incoming.layer.removeAllAnimations()
        setOpacity(incoming.layer, 1)
        let old = current
        current = incoming
        self.incoming = nil
        incomingReady = false
        incomingForced = false
        currentEnded = false
        fading = false
        old?.teardown()
        if nextOverride != nil { prepareNext() }
    }

    // MARK: Katman yardımcıları

    private func attach(_ instance: LoopInstance, opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        instance.layer.frame = host.bounds
        instance.layer.opacity = opacity
        host.addSublayer(instance.layer)       // sonradan eklenen üstte: gelen katman eskinin üzerinde belirir
        CATransaction.commit()
    }

    private func setOpacity(_ layer: CALayer, _ value: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = value
        CATransaction.commit()
    }
}
