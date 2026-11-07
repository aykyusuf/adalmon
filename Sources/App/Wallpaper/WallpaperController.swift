import AppKit
import AVFoundation
import Observation

/// Seçenek A: her ekran için masaüstü seviyesinde bir pencere + AVPlayerLayer. Kapalıyken HİÇBİR şey yoktur
/// (pencere, zamanlayıcı, gözlemci). Duraklatılmışken kare çözülmez; son kare katmanda kalır.
@MainActor @Observable
final class WallpaperController {
    struct Config: Equatable {
        var settings = WallpaperSettings()
        var items: [WallpaperItem] = []
        var override: WallpaperUserOverride = .auto
    }

    struct ScreenStatus: Identifiable, Equatable {
        var screen: WallpaperScreenInfo
        var itemName: String?
        var decision: WallpaperDecision?
        var id: String { screen.key }
    }

    enum Summary: Equatable {
        case off
        case noContent
        case playing(String)
        case still(String)
        case paused(WallpaperPauseReason, String)

        var text: String {
            switch self {
            case .off: "Kapalı"
            case .noContent: "İçerik seçilmedi"
            case .playing(let detail): "Oynatılıyor · \(detail)"
            case .still(let detail): "Sabit görüntü · \(detail)"
            case .paused(let reason, _): reason.statusText
            }
        }
        var isPlaying: Bool { if case .playing = self { true } else { false } }
        var symbol: String {
            switch self {
            case .off: "power"
            case .noContent: "photo.badge.plus"
            case .playing: "play.circle.fill"
            case .still: "photo"
            case .paused: "pause.circle.fill"
            }
        }
    }

    private(set) var summary: Summary = .off
    private(set) var screenStatuses: [ScreenStatus] = []
    /// Bağlı ekranlar (ayarlar sayfasındaki atama listesi için); özellik kapalıyken boş.
    private(set) var screens: [WallpaperScreenInfo] = []

    // MARK: Bağımlılıklar (testte değiştirilir)

    /// Pencere / gözlemci / zamanlayıcı oluşturmaz; yalnızca kararları hesaplar (birim testleri için).
    @ObservationIgnored let isHeadless: Bool
    @ObservationIgnored var screenProvider: @MainActor () -> [LiveScreen]
    @ObservationIgnored var occlusionProvider: @MainActor ([WallpaperScreenInfo]) -> [String: OcclusionCheck.Result]
    @ObservationIgnored let monitor = WallpaperSystemMonitor()

    struct LiveScreen {
        var info: WallpaperScreenInfo
        var frame: NSRect
    }

    // MARK: Durum

    @ObservationIgnored private(set) var config = Config()
    @ObservationIgnored private var slots: [String: Slot] = [:]
    @ObservationIgnored private var occlusion: [String: OcclusionCheck.Result] = [:]
    @ObservationIgnored private var rotation = PlaylistRotation(ids: [], mode: .single)
    @ObservationIgnored private var observersActive = false
    @ObservationIgnored private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var rotationTimer: Timer?
    @ObservationIgnored private var rotationRemaining: TimeInterval?
    @ObservationIgnored private var activity: NSObjectProtocol?

    init(isHeadless: Bool = false,
         screenProvider: @escaping @MainActor () -> [LiveScreen] = WallpaperController.liveScreens,
         occlusionProvider: @escaping @MainActor ([WallpaperScreenInfo]) -> [String: OcclusionCheck.Result] = WallpaperController.liveOcclusion) {
        self.isHeadless = isHeadless
        self.screenProvider = screenProvider
        self.occlusionProvider = occlusionProvider
    }

    // MARK: Giriş noktası

    func apply(_ newConfig: Config) {
        let was = config
        config = newConfig
        guard newConfig.settings.enabled else {
            if was.settings.enabled || observersActive || !slots.isEmpty { teardown() }
            summary = .off
            screenStatuses = []
            screens = []
            return
        }
        startObserversIfNeeded()
        syncRotation(previous: was)
        rebuildScreens()
        reevaluate(poll: true)
    }

    // MARK: Ekranlar ve içerik

    private func rebuildScreens() {
        let live = screenProvider()
        let unique = ScreenMapping.unique(live.map(\.info))
        screens = unique
        let available = Set(config.items.filter(\.fileExists).map(\.id))
        let assigned = ScreenMapping.assignments(screens: unique, sameOnAll: config.settings.sameOnAllScreens, defaultItem: effectiveDefaultItem,
                                                 perScreen: config.settings.perScreen, available: available)
        let byID = Dictionary(config.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        for entry in live where seen.insert(entry.info.key).inserted {
            guard let itemID = assigned[entry.info.key], let item = byID[itemID] else {
                if let slot = slots.removeValue(forKey: entry.info.key) { slot.teardown() }
                continue
            }
            let slot: Slot
            if let existing = slots[entry.info.key] { slot = existing }
            else {
                slot = Slot(key: entry.info.key, frame: entry.frame, headless: isHeadless)
                slots[entry.info.key] = slot
            }
            slot.update(frame: entry.frame, scale: entry.info.scale, pixelSize: entry.info.pixelSize)
            slot.assign(item)
        }
        for key in slots.keys where !seen.contains(key) {
            slots.removeValue(forKey: key)?.teardown()
        }
    }

    private var effectiveDefaultItem: UUID? {
        config.settings.playlistMode == .single ? config.settings.defaultItemID : (rotation.current ?? config.settings.defaultItemID)
    }

    private func syncRotation(previous: Config) {
        let ids = config.items.filter(\.fileExists).map(\.id)
        let s = config.settings
        if previous.settings.playlistMode != s.playlistMode || previous.settings.defaultItemID != s.defaultItemID || rotation.ids.isEmpty {
            rotation = PlaylistRotation(ids: ids, mode: s.playlistMode, current: s.defaultItemID)
            rotationRemaining = nil
        } else {
            rotation.update(ids: ids)
        }
        if previous.settings.rotationMinutes != s.rotationMinutes { rotationRemaining = nil; rotationTimer?.invalidate(); rotationTimer = nil }
    }

    // MARK: Karar

    /// Politikayı her ekran için uygular. `poll`: örtülme bilgisi yeniden okunsun.
    func reevaluate(poll: Bool) {
        guard config.settings.enabled else { return }
        let rules = config.settings.rules
        if poll { refreshOcclusion() }
        let sys = monitor.state
        var statuses: [ScreenStatus] = []
        let byID = Dictionary(config.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for info in screens {
            guard let slot = slots[info.key], let itemID = slot.itemID else {
                statuses.append(ScreenStatus(screen: info, itemName: nil, decision: nil))
                continue
            }
            let occ = occlusion[info.key] ?? OcclusionCheck.Result(coverage: 0, fullScreen: false)
            let input = WallpaperPolicyInput(onBattery: sys.onBattery, lowPower: sys.lowPower,
                                             desktopVisible: !OcclusionCheck.isCovered(occ),
                                             locked: monitor.policyLocked, displayAsleep: sys.displayAsleep, fullScreen: occ.fullScreen)
            let decision = WallpaperPolicy.decide(input, rules: rules, override: config.override)
            slot.apply(decision: decision)
            statuses.append(ScreenStatus(screen: info, itemName: byID[itemID]?.name, decision: decision))
        }
        screenStatuses = statuses
        updateSummary(byID: byID)
        updateTimers()
    }

    private func updateSummary(byID: [UUID: WallpaperItem]) {
        let active = screenStatuses.filter { $0.decision != nil }
        guard !active.isEmpty else { summary = .noContent; return }
        func item(for s: ScreenStatus) -> WallpaperItem? { slots[s.id]?.itemID.flatMap { byID[$0] } }
        // Önce oynayan bir video, yoksa duraklatılan, yoksa sabit görüntü.
        if let playing = active.first(where: { $0.decision == .play && item(for: $0)?.kind == .video }), let it = item(for: playing) {
            summary = .playing(Self.detail(it)); return
        }
        if let paused = active.first(where: { if case .pause = $0.decision { item(for: $0)?.kind == .video } else { false } }),
           case .pause(let reason)? = paused.decision, let it = item(for: paused) {
            summary = .paused(reason, Self.detail(it)); return
        }
        if let it = active.compactMap({ item(for: $0) }).first { summary = .still(Self.detail(it)) }
    }

    static func detail(_ item: WallpaperItem) -> String {
        let q: String
        if item.kind == .image, let i = item.info { q = "\(i.width) × \(i.height)" } else { q = item.info?.qualityText ?? item.name }
        return "\(q) · \(WallpaperEnergyEstimate.estimate(kind: item.kind, info: item.info).text)"
    }

    // MARK: Zamanlayıcılar (yalnızca gerektiğinde)

    private var anyVideoSlot: Bool { slots.values.contains { $0.isVideo } }

    private var shouldPoll: Bool {
        guard !isHeadless, config.settings.rules.pauseWhenDesktopHidden else { return false }
        // Fiziksel/pil sebebiyle durmuşken yoklama gerekmez (olay gelince yeniden değerlendirilir).
        return screenStatuses.contains { s in
            guard let d = s.decision, slots[s.id]?.isVideo == true else { return false }
            switch d {
            case .play, .pause(.covered), .pause(.fullScreen): return true
            default: return false
            }
        }
    }

    private var anyPlaying: Bool { screenStatuses.contains { $0.decision == .play && slots[$0.id]?.isVideo == true } }

    private func updateTimers() {
        guard !isHeadless else { return }
        if shouldPoll {
            if pollTimer == nil {
                let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.pollTick() }
                }
                t.tolerance = 0.5
                RunLoop.main.add(t, forMode: .common)
                pollTimer = t
            }
        } else {
            pollTimer?.invalidate(); pollTimer = nil
        }
        // App Nap yoklamayı geciktirmesin: yalnızca video OYNARKEN etkinlik bildirimi (boşta uykuya izin verir).
        if anyPlaying {
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Canlı duvar kâğıdı oynatılıyor")
            }
        } else if let a = activity {
            ProcessInfo.processInfo.endActivity(a); activity = nil
        }
        updateRotationTimer()
    }

    private func updateRotationTimer() {
        let s = config.settings
        let wants = s.playlistMode != .single && rotation.ids.count > 1 && (anyPlaying || (!anyVideoSlot && !slots.isEmpty))
        if wants {
            guard rotationTimer == nil else { return }
            let interval = rotationRemaining ?? TimeInterval(max(1, s.rotationMinutes) * 60)
            let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.rotationFired() }
            }
            t.tolerance = min(30, interval * 0.1)
            RunLoop.main.add(t, forMode: .common)
            rotationTimer = t
            rotationRemaining = interval
        } else if let t = rotationTimer {
            rotationRemaining = max(1, t.fireDate.timeIntervalSinceNow)
            t.invalidate(); rotationTimer = nil
        }
    }

    private func rotationFired() {
        rotationTimer = nil
        rotationRemaining = nil
        rotation.advance()
        rebuildScreens()
        reevaluate(poll: false)
    }

    /// Sıradaki içeriğe elle geç (UI düğmesi).
    func advanceNow() {
        guard config.settings.enabled, config.settings.playlistMode != .single else { return }
        rotationTimer?.invalidate(); rotationTimer = nil
        rotationFired()
    }

    private func pollTick() {
        let before = occlusion
        refreshOcclusion()
        if before != occlusion { reevaluate(poll: false) }
    }

    private func refreshOcclusion() {
        guard config.settings.rules.pauseWhenDesktopHidden, anyVideoSlot else { occlusion = [:]; return }
        occlusion = occlusionProvider(screens)
    }

    // MARK: Gözlemciler

    private func startObserversIfNeeded() {
        guard !isHeadless, !observersActive else { return }
        observersActive = true
        monitor.onChange = { [weak self] in self?.reevaluate(poll: true) }
        monitor.start()
        func add(_ name: Notification.Name, _ center: NotificationCenter = .default, _ body: @escaping @MainActor (WallpaperController) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            }
            notificationTokens.append((center, token))
        }
        let ws = NSWorkspace.shared.notificationCenter
        add(NSApplication.didChangeScreenParametersNotification) { $0.rebuildScreens(); $0.reevaluate(poll: true) }
        add(NSWorkspace.activeSpaceDidChangeNotification, ws) { $0.reevaluate(poll: true) }
        add(NSWorkspace.didActivateApplicationNotification, ws) { $0.reevaluate(poll: true) }
    }

    private func teardown() {
        pollTimer?.invalidate(); pollTimer = nil
        rotationTimer?.invalidate(); rotationTimer = nil
        rotationRemaining = nil
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        for (center, token) in notificationTokens { center.removeObserver(token) }
        notificationTokens = []
        monitor.stop()
        monitor.onChange = nil
        observersActive = false
        for slot in slots.values { slot.teardown() }
        slots = [:]
        occlusion = [:]
    }

    // MARK: Canlı ekran bilgisi

    static func liveScreens() -> [LiveScreen] {
        NSScreen.screens.compactMap { screen in
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(num.uint32Value)
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(), let str = CFUUIDCreateString(nil, uuid) as String? else { return nil }
            let scale = screen.backingScaleFactor
            let info = WallpaperScreenInfo(key: str, name: screen.localizedName, pixelSize: CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale),
                                           scale: scale, cgBounds: CGDisplayBounds(id), isMain: id == CGMainDisplayID())
            return LiveScreen(info: info, frame: screen.frame)
        }
    }

    static func liveOcclusion(_ screens: [WallpaperScreenInfo]) -> [String: OcclusionCheck.Result] {
        let windows = OcclusionCheck.liveWindows()
        var out: [String: OcclusionCheck.Result] = [:]
        for s in screens { out[s.key] = OcclusionCheck.analyze(windows: windows, display: s.cgBounds, excludingPID: nil) }
        return out
    }
}

// MARK: - Ekran dilimi

/// Bir ekranın penceresi + oynatıcısı. Aynı anda yalnızca BİR AVPlayer tutulur (asset değişiminde sızıntı raporu).
@MainActor
private final class Slot {
    let key: String
    let headless: Bool
    private var window: WallpaperWindow?
    private var content: WallpaperContentView?
    private(set) var itemID: UUID?
    private var item: WallpaperItem?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    private var scale: CGFloat = 2
    private var pixelSize = CGSize(width: 3000, height: 2000)
    private var token = UUID()
    private var lastDecision: WallpaperDecision?

    var isVideo: Bool { item?.kind == .video }

    init(key: String, frame: NSRect, headless: Bool) {
        self.key = key
        self.headless = headless
        guard !headless else { return }
        let w = WallpaperWindow(frame: frame)
        let c = WallpaperContentView(frame: NSRect(origin: .zero, size: frame.size))
        c.autoresizingMask = [.width, .height]
        w.contentView = c
        window = w
        content = c
    }

    func update(frame: NSRect, scale: CGFloat, pixelSize: CGSize) {
        self.scale = scale
        self.pixelSize = pixelSize
        guard let window, window.frame != frame else { return }
        window.setFrame(frame, display: true)
    }

    func assign(_ newItem: WallpaperItem) {
        if let item, item.id == newItem.id, item.path == newItem.path { self.item = newItem; return }
        stopPlayback()
        item = newItem
        itemID = newItem.id
        token = UUID()
        lastDecision = nil
        guard let content else { return }
        content.playerLayer.isHidden = true
        let myToken = token
        let maxPixel = Int(max(pixelSize.width, pixelSize.height))
        let url = newItem.url, kind = newItem.kind
        // Poster / sabit görüntü: arka planda yüklenir (ana iş parçacığını bloklamaz), ekran boyutuna indirilir.
        Task { [weak self] in
            let image: CGImage?
            if kind == .image {
                image = await Task.detached(priority: .utility) { WallpaperMedia.downsampledImage(url, maxPixel: maxPixel) }.value
            } else {
                image = await WallpaperMedia.frameImage(url, kind: kind, maxPixel: maxPixel, at: 1)
            }
            guard let self, self.token == myToken else { return }
            self.crossfadeStill(image)
        }
        window?.orderBack(nil)
    }

    private func crossfadeStill(_ image: CGImage?) {
        guard let content else { return }
        content.setStill(image, scale: scale)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.6
        content.stillLayer.add(fade, forKey: "fade")
    }

    func apply(decision: WallpaperDecision) {
        defer { lastDecision = decision }
        guard let item, item.kind == .video else { return }
        if case .pause(let reason) = lastDecision, decision == .play, reason == .displayAsleep || reason == .locked {
            content?.playerLayer.player = nil   // uyku / kilit sonrası katmanı yeniden bağla (siyah kare önlemi)
            content?.playerLayer.player = player
        }
        switch decision {
        case .play:
            ensurePlayer(item)
            player?.play()
        case .pause:
            player?.pause()
        }
    }

    private func ensurePlayer(_ item: WallpaperItem) {
        guard player == nil, let content else { return }
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        queue.automaticallyWaitsToMinimizeStalling = false
        let template = AVPlayerItem(url: item.url)
        looper = AVPlayerLooper(player: queue, templateItem: template)   // güçlü referans şart
        content.playerLayer.player = queue
        player = queue
        readyObservation = content.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            MainActor.assumeIsolated { self?.revealPlayer() }
        }
    }

    private func revealPlayer() {
        guard let content, content.playerLayer.isHidden else { return }
        content.playerLayer.opacity = 0
        content.playerLayer.isHidden = false
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.6
        content.playerLayer.opacity = 1
        content.playerLayer.add(fade, forKey: "fade")
    }

    private func stopPlayback() {
        readyObservation = nil
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        content?.playerLayer.player = nil
        player = nil
    }

    func teardown() {
        stopPlayback()
        token = UUID()
        window?.orderOut(nil)
        window?.contentView = nil
        window?.close()
        window = nil
        content = nil
        item = nil
        itemID = nil
    }
}
