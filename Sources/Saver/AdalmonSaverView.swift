import AVFoundation
import AppKit
import ScreenSaver

/// Adalmon Video ekran koruyucusu. Videolar `SaverPaths.sharedDirectory` altındaki `playlist.json`'dan okunur
/// (mutlak yol: sandbox'lı ana süreç `/` altını salt okunur açabilir; `~` konteynere yönlenir, KULLANILMAZ).
@objc(AdalmonSaverView)
final class AdalmonSaverView: ScreenSaverView {
    private static var nextToken = 0

    let token: Int
    private let rootLayer = CALayer()
    private let playback = SaverPlayback()
    private let messageLayer = CATextLayer()
    private var occlusionObserver: NSObjectProtocol?
    private var started = false
    private var previewFlag = false
    private var playlist: SaverPlaylist?
    private var resolved: [SaverPlaylist.Resolved] = []

    private var effectivePreview: Bool {
        SaverPreviewHeuristic.isPreview(flag: previewFlag, size: bounds.size)
    }

    override init?(frame: NSRect, isPreview: Bool) {
        Self.nextToken += 1
        token = Self.nextToken
        previewFlag = isPreview
        super.init(frame: frame, isPreview: isPreview)
        configure()
    }

    required init?(coder: NSCoder) {
        Self.nextToken += 1
        token = Self.nextToken
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        animationTimeInterval = 60          // çizim yok: zamanlayıcı neredeyse hiç uyanmasın
        rootLayer.backgroundColor = NSColor.black.cgColor
        rootLayer.contentsGravity = .resizeAspectFill
        rootLayer.masksToBounds = true
        layer = rootLayer           // önce katman, sonra wantsLayer: katman-barındıran görünüm
        wantsLayer = true
        rootLayer.addSublayer(playback.layer)
        messageLayer.alignmentMode = .center
        messageLayer.isWrapped = true
        messageLayer.foregroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
        messageLayer.isHidden = true
        rootLayer.addSublayer(messageLayer)
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
    override func animateOneFrame() {}

    // MARK: Yaşam döngüsü

    override func startAnimation() {
        super.startAnimation()
        guard !started else { return }
        started = true
        loadPlaylist()
        SaverHost.shared.register(self, screenKey: screenKey(), isPreview: effectivePreview, hostExitOnStop: playlist?.hostExitOnStop ?? true)
        applyMode()
    }

    override func stopAnimation() {
        super.stopAnimation()
        teardown()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        guard let window else { teardown(); return }
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playback.layer.frame = bounds
        messageLayer.frame = bounds.insetBy(dx: 40, dy: bounds.height / 2 - 40)
        messageLayer.fontSize = effectivePreview ? 9 : 22
        CATransaction.commit()
        if started {
            SaverHost.shared.reclassify(self, isPreview: effectivePreview)
            applyMode()
        }
    }

    /// Sunucudan: yeni örnek geldi / `willstop`. Oynatıcıyı bırakır, kayıttan çıkar.
    func evict() { teardown() }

    private func teardown() {
        guard started || playback.isActive else { return }
        started = false
        playback.stop()
        SaverHost.shared.unregister(self)
    }

    private func occlusionChanged() {
        guard started, playback.isActive, let window else { return }
        playback.setPaused(!window.occlusionState.contains(.visible))
    }

    // MARK: İçerik

    private func screenKey() -> String {
        if let number = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return "view-\(token)"          // ekran bilinmiyor: benzersiz, başka ekranın örneğini atmaz
    }

    private func loadPlaylist() {
        let dir = SaverPaths.sharedDirectory
        playlist = SaverPlaylist.load(from: dir)
        resolved = playlist?.playable(in: dir) ?? []
    }

    private func applyMode() {
        guard started else { return }
        guard !resolved.isEmpty else {
            showPoster(preferring: nil)
            playback.stop()
            showMessage(playlist == nil ? "Adalmon Video: oynatma listesi okunamadı.\nAdalmon > Duvar kâğıdı > Ekran koruyucu'dan videoları hazırlayın."
                                        : "Adalmon Video: listedeki videolar bulunamadı.")
            return
        }
        messageLayer.isHidden = true
        if effectivePreview {
            showPoster(preferring: nil)
            playback.stop()                 // küçük önizleme: 4K çözme yok, yalnızca poster
        } else if !playback.isActive {
            var rng = SystemRandomNumberGenerator()
            let list = playlist ?? SaverPlaylist(appVersion: "", updatedAt: .now, shuffle: false, items: [])
            let order = list.order(resolved, using: &rng)
            // Poster ANINDA görünür (siyah ekran yok); video katmanı ilk kare hazır olunca üstünde belirir.
            showPoster(preferring: order.first)
            playback.start(sources: order.map { LoopSource(url: $0.videoURL, duration: $0.item.duration) }, timing: list.timing)
        }
    }

    /// İlk oynayacak videonun posteri (kırpma başlangıcındaki kare); yoksa herhangi bir poster.
    private func showPoster(preferring first: SaverPlaylist.Resolved?) {
        guard rootLayer.contents == nil,
              let url = first?.posterURL ?? resolved.first(where: { $0.posterURL != nil })?.posterURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        rootLayer.contents = image
    }

    private func showMessage(_ text: String) {
        messageLayer.string = text
        messageLayer.contentsScale = window?.backingScaleFactor ?? 2
        messageLayer.isHidden = false
    }
}
