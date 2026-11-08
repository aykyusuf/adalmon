import AVFoundation
import AppKit
import ImageIO
import ScreenSaver
import os

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
    /// `init`'te hesaplanan oynatma sırası: ilk `startAnimation` bunu kullanır (poster ile ilk video aynı olsun).
    /// Tüketilince / durdurulunca `nil`; yeniden başlatmada liste diskten tazelenir.
    private var pendingOrder: [SaverPlaylist.Resolved]?
    private var shownPosterURL: URL?
    private let createdAt = ContinuousClock.now
    private var startedAt: ContinuousClock.Instant?

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
        SaverTrace.event("init", "view=\(token) preview=\(previewFlag) size=\(Int(frame.width))x\(Int(frame.height)) sinceProcessStart=\(SaverTrace.msSinceProcessStart())ms")
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
        prepareContent()
    }

    /// Soğuk başlangıç: listeyi okur, sırayı belirler ve ilk videonun posterini EŞZAMANLI (çözülmüş olarak) katmana koyar.
    /// Böylece pencere ilk kez çizildiğinde poster zaten oradadır; `startAnimation`'ı beklemez. Oynatıcı burada KURULMAZ:
    /// ekran bilinmez (kayıt / ezme yapılamaz) ve macOS'un yığılan örnek hatasında sahipsiz çözücüler kalırdı.
    private func prepareContent() {
        let begin = ContinuousClock.now
        loadPlaylist()
        let order = makeOrder()
        pendingOrder = order
        showPoster(preferring: order.first)
        SaverTrace.event("contentReady", "view=\(token) items=\(resolved.count) poster=\(shownPosterURL != nil) took=\(SaverTrace.ms(ContinuousClock.now - begin))ms")
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
    override func animateOneFrame() {}

    // MARK: Yaşam döngüsü

    override func startAnimation() {
        super.startAnimation()
        guard !started else { return }
        started = true
        startedAt = .now
        SaverTrace.event("startAnimation", "view=\(token) sinceInit=\(SaverTrace.ms(ContinuousClock.now - createdAt))ms reusedInitContent=\(pendingOrder != nil)")
        if pendingOrder == nil {
            // Yeniden başlatma (durdurulduktan sonra): liste değişmiş olabilir.
            loadPlaylist()
            let order = makeOrder()
            pendingOrder = order
            showPoster(preferring: order.first)
        }
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
        SaverTrace.event("didMoveToWindow", "view=\(token) sinceInit=\(SaverTrace.ms(ContinuousClock.now - createdAt))ms")
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
        pendingOrder = nil
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

    private func makeOrder() -> [SaverPlaylist.Resolved] {
        guard let playlist else { return resolved }
        var rng = SystemRandomNumberGenerator()
        return playlist.order(resolved, using: &rng)
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
            showPoster(preferring: pendingOrder?.first)
            playback.stop()                 // küçük önizleme: 4K çözme yok, yalnızca poster
        } else if !playback.isActive {
            let order = pendingOrder ?? makeOrder()
            pendingOrder = order            // aynı oturumda (layout → applyMode) sıra değişmesin
            let timing = (playlist ?? SaverPlaylist(appVersion: "", updatedAt: .now, shuffle: false, items: [])).timing
            // Poster zaten init'te görünür (siyah ekran yok); video katmanı ilk kare hazır olunca üstünde belirir.
            showPoster(preferring: order.first)
            let token = token, startedAt = startedAt ?? .now, createdAt = createdAt
            playback.onFirstFrame = {
                let now = ContinuousClock.now
                SaverTrace.event("firstFrame", "view=\(token) sinceStart=\(SaverTrace.ms(now - startedAt))ms sinceInit=\(SaverTrace.ms(now - createdAt))ms")
            }
            playback.start(sources: order.map { LoopSource(url: $0.videoURL, duration: $0.item.duration) }, timing: timing)
        }
    }

    /// İlk oynayacak videonun posteri (kırpma başlangıcındaki kare); yoksa herhangi bir poster. Aynı poster yeniden çözülmez.
    private func showPoster(preferring first: SaverPlaylist.Resolved?) {
        guard let url = first?.posterURL ?? resolved.first(where: { $0.posterURL != nil })?.posterURL,
              url != shownPosterURL else { return }
        let begin = ContinuousClock.now
        guard let image = Self.decodePoster(at: url) else { return }
        // Örtük `contents` animasyonu (siyahtan ~0,25 sn solma) olmasın: poster ANINDA görünür.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.contents = image
        CATransaction.commit()
        shownPosterURL = url
        SaverTrace.event("posterShown", "view=\(token) \(image.width)x\(image.height) decode=\(SaverTrace.ms(ContinuousClock.now - begin))ms")
    }

    /// JPEG'i HEMEN çözer (`ShouldCacheImmediately`): çözme ilk çizimde (ana iş parçacığında, commit sırasında) değil burada olur.
    /// Posterler zaten küçük (uygulama ~960 px üretir), ayrıca küçültme gerekmez.
    nonisolated static func decodePoster(at url: URL) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }

    private func showMessage(_ text: String) {
        messageLayer.string = text
        messageLayer.contentsScale = window?.backingScaleFactor ?? 2
        messageLayer.isHidden = false
    }
}

/// Soğuk başlangıç ölçümleri: `log stream --predicate 'subsystem == "com.example.adalmon" AND category == "saver"'`.
/// Yalnızca başlangıç olaylarında yazar (döngü sırasında hiçbir şey yok).
enum SaverTrace {
    static let logger = Logger(subsystem: "com.example.adalmon", category: "saver")
    static let signposter = OSSignposter(logger: logger)

    static func event(_ name: StaticString, _ detail: String) {
        signposter.emitEvent(name, "\(detail, privacy: .public)")
        logger.notice("\(String(describing: name), privacy: .public) \(detail, privacy: .public)")
    }

    static func ms(_ duration: Duration) -> Int {
        let c = duration.components
        return Int(c.seconds * 1000 + c.attoseconds / 1_000_000_000_000_000)
    }

    /// Ana sürecin (legacyScreenSaver) başlamasından bu yana geçen süre: sistemin kendi açılış payını gösterir.
    static func msSinceProcessStart() -> Int {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return -1 }
        let start = info.kp_proc.p_un.__p_starttime
        var now = timeval()
        gettimeofday(&now, nil)
        return (now.tv_sec - start.tv_sec) * 1000 + Int(now.tv_usec - start.tv_usec) / 1000
    }
}
