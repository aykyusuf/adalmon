import AppKit
import SpriteKit

/// Fare olaylarını hiç almayan SKView (masaüstü penceresi zaten `ignoresMouseEvents`; bu ikinci güvence).
final class OfficeWallpaperView: SKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
}

/// Ofis duvar kâğıdının pencere içeriği: SKView + OfficeScene + duraklatma bağlantısı. SwiftUI'ya bağımlı değil.
/// Performans: 10 kare/sn; politika duraklatınca ya da sahnede animasyon yokken `isPaused = true` (son kare kalır, CPU ≈ 0).
/// Sahne ayrı bir `OfficeScene` örneğidir; oda dokuları paylaşılan `OfficeAssets.shared` önbelleğinden gelir (ikinci kopya yok).
@MainActor
final class OfficeWallpaperHost {
    static let framesPerSecond = 10

    let view: OfficeWallpaperView
    private(set) var scene: OfficeScene?
    private(set) var isPlaying = false
    private var members: [OfficeMember] = []
    /// Duraklatılmışken gelen üyeler: devam edince uygulanır (duraklıyken sahne kurulmaz).
    private var pendingMembers: [OfficeMember]?
    private var needsFrame = true
    private var pauseTask: Task<Void, Never>?
    private var wanderTimer: Timer?
    private var options = OfficeWallpaperOptions()
    private var theme = OfficeTheme.default

    init(size: CGSize) {
        view = OfficeWallpaperView(frame: NSRect(origin: .zero, size: size))
        view.preferredFramesPerSecond = Self.framesPerSecond
        view.ignoresSiblingOrder = true
        view.allowsTransparency = false
        view.autoresizingMask = [.width, .height]
        view.isPaused = true
        guard let assets = OfficeAssets.shared else { return }
        let scene = OfficeScene(assets: assets, size: size, theme: theme)
        scene.onAnimationStateChange = { [weak self] _ in self?.refreshRunState() }
        scene.onActivity = { [weak self] in self?.needsFrame = true; self?.refreshRunState() }
        // "Otomatik" arka plan: gece/gündüz değişince Koyu ↔ Açık yeniden çözülür.
        scene.onNightChange = { [weak self] _ in self?.applyBackground() }
        self.scene = scene
        view.presentScene(scene)
    }

    /// Seçenekler/tema değişince çağrılır; yalnızca değişen kısım sahneye uygulanır.
    func configure(options newOptions: OfficeWallpaperOptions, theme newTheme: OfficeTheme) {
        guard let scene else { return }
        var changed = false
        let oldBackground = options.background
        options.background = newOptions.background   // ışık değişimi "Otomatik" arka planı yeni seçimle çözsün
        if newTheme != theme { theme = newTheme; scene.setTheme(newTheme); changed = true }
        if newOptions.lighting != options.lighting || scene.wallpaperLabels == nil {
            scene.setLightingMode(newOptions.lighting, animated: false); changed = true
        }
        if scene.wallpaperLabels == nil || newOptions.background != oldBackground { applyBackground(); changed = true }
        if newOptions.labels != scene.wallpaperLabels { scene.wallpaperLabels = newOptions.labels; changed = true }
        options = newOptions
        if changed { needsFrame = true; applyMembers(members); refreshRunState() }
    }

    /// Arka planı seçime göre uygular; "Otomatik" ise sahnenin gece/gündüz durumuna bakar.
    private func applyBackground() {
        guard let scene else { return }
        scene.setBackdropStyle(options.background.resolved(night: scene.isNight).style)
        needsFrame = true
        refreshRunState()
    }

    func setMembers(_ new: [OfficeMember]) {
        guard new != members || pendingMembers != nil else { return }
        if isPlaying { applyMembers(new) } else { pendingMembers = new; members = new }
        refreshRunState()
    }

    private func applyMembers(_ new: [OfficeMember]) {
        members = new
        pendingMembers = nil
        scene?.apply(members: new, animated: false)
    }

    /// Politika kararı: true → çiz, false → duraklat (son kare kalır).
    func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        isPlaying = playing
        if playing, let pending = pendingMembers { applyMembers(pending); needsFrame = true }
        else if playing { needsFrame = true }
        refreshRunState()
    }

    /// SKView çalışsın mı: yalnızca (politika oynat) VE (sahnede animasyon var ya da son kare henüz çizilmedi).
    private func refreshRunState() {
        pauseTask?.cancel()
        guard scene != nil else { return }
        if isPlaying, scene?.isAnimating == true {
            view.isPaused = false
            needsFrame = false
        } else if needsFrame || (isPlaying && view.isPaused == false) {
            // Son kare çizilsin, sonra durakla.
            view.isPaused = false
            pauseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self else { return }
                self.needsFrame = false
                self.view.isPaused = !(self.isPlaying && self.scene?.isAnimating == true)
            }
        } else {
            view.isPaused = true
        }
        updateWanderTimer(active: isPlaying && (scene?.actorCount ?? 0) > 0)
    }

    /// Kahve yürüyüşü / boşta varyantları: yalnızca oynarken ve karakter varken tek düşük frekanslı zamanlayıcı.
    private func updateWanderTimer(active: Bool) {
        if active, wanderTimer == nil {
            let timer = Timer(timeInterval: 12, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isPlaying, let scene = self.scene else { return }
                    if scene.wanderTick() { self.refreshRunState() }
                }
            }
            timer.tolerance = 6
            RunLoop.main.add(timer, forMode: .common)
            wanderTimer = timer
        } else if !active {
            wanderTimer?.invalidate()
            wanderTimer = nil
        }
    }

    /// Sahneyi ve zamanlayıcıları bırakır (kaynak değişimi / ekran ayrılması / özellik kapanması).
    func shutdown() {
        pauseTask?.cancel(); pauseTask = nil
        wanderTimer?.invalidate(); wanderTimer = nil
        view.isPaused = true
        view.presentScene(nil)
        scene?.onAnimationStateChange = nil
        scene?.onActivity = nil
        scene?.shutdown()
        scene = nil
        members = []
        pendingMembers = nil
    }
}

/// Bir ekranın ofis duvar kâğıdı dilimi: masaüstü seviyesinde pencere + `OfficeWallpaperHost`. Headless'ta pencere/sahne yoktur,
/// yalnızca durum tutulur (birim testleri).
@MainActor
final class OfficeSlot {
    let key: String
    let headless: Bool
    private var window: WallpaperWindow?
    private var host: OfficeWallpaperHost?
    private(set) var lastDecision: WallpaperDecision?
    private(set) var members: [OfficeMember] = []
    private(set) var options = OfficeWallpaperOptions()
    private(set) var theme = OfficeTheme.default

    init(key: String, frame: NSRect, headless: Bool) {
        self.key = key
        self.headless = headless
        guard !headless else { return }
        let w = WallpaperWindow(frame: frame)
        let h = OfficeWallpaperHost(size: frame.size)
        w.contentView = h.view
        window = w
        host = h
        w.orderBack(nil)
    }

    var hasWindow: Bool { window != nil }

    func update(frame: NSRect) {
        guard let window, window.frame != frame else { return }
        window.setFrame(frame, display: true)
    }

    func configure(options: OfficeWallpaperOptions, theme: OfficeTheme, members: [OfficeMember]) {
        self.options = options
        self.theme = theme
        self.members = members
        host?.configure(options: options, theme: theme)
        host?.setMembers(members)
    }

    func setMembers(_ new: [OfficeMember]) {
        guard new != members else { return }
        members = new
        host?.setMembers(new)
    }

    func apply(decision: WallpaperDecision) {
        lastDecision = decision
        host?.setPlaying(decision == .play)
    }

    func teardown() {
        host?.shutdown()
        window?.orderOut(nil)
        window?.contentView = nil
        window?.close()
        window = nil
        host = nil
        members = []
        lastDecision = nil
    }
}
