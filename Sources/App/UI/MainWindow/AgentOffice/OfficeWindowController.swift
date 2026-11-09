import AppKit
import SwiftUI

/// Ayrı "Ajan ofisi" penceresi (tek örnek). SwiftUI içeriği yalnızca pencere açıkken vardır: kapanınca hosting controller
/// bırakılır, sahne sökülür (`OfficeSceneView.dismantleNSView` → `tearDown`) ve model boşuna gözlemlenmez (pil).
/// Duraklatma (örtülü/küçültülmüş/gizli) `OfficeHostView` tarafından aynen uygulanır.
@MainActor
final class OfficeWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let defaults: UserDefaults
    let window: NSWindow
    let state: OfficeWindowState

    static let minContentSize = OfficeWindowFrame.minSize

    private let keepAwake: OfficeKeepAwake
    private var activityMonitor: Any?
    private var hideTimer: Timer?
    private var lastActivity = Date()
    private var occlusionObserver: NSObjectProtocol?

    init(model: AppModel, defaults: UserDefaults = .standard, assertion: any DisplaySleepAsserting = IOKitDisplaySleepAssertion()) {
        self.model = model
        self.defaults = defaults
        keepAwake = OfficeKeepAwake(assertion: assertion)
        state = OfficeWindowState(settings: OfficeWindowSettings.load(from: defaults))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: OfficeWindowFrame.defaultSize),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        super.init()
        window.title = "Ajan ofisi"
        window.contentMinSize = Self.minContentSize
        window.isReleasedWhenClosed = false
        window.delegate = self
        let screens = NSScreen.screens.map(\.visibleFrame)
        if let saved = OfficeWindowFrame.decode(defaults.object(forKey: OfficeWindowFrame.defaultsKey), visibleFrames: screens) {
            window.setFrame(saved, display: false)
        } else if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            window.setFrame(OfficeWindowFrame.defaultFrame(visible: visible), display: false)
        } else {
            window.center()
        }
        state.settings.apply(to: window)
        state.onSettingsChange = { [weak self] settings in
            guard let self else { return }
            settings.apply(to: window)
            settings.save(to: self.defaults)
            self.refreshPanoServices()
        }
        state.onToggleFullScreen = { [weak self] in self?.window.toggleFullScreen(nil) }
    }

    /// Pencere açık mı (küçültülmüş veya örtülü olsa bile)? Kapatılınca içerik bırakıldığı için içeriğe bakılır.
    var isOpen: Bool { window.contentViewController != nil }

    /// Açar; zaten açıksa aynı pencereyi öne getirir (küçültülmüşse geri açar).
    func show() {
        if window.contentViewController == nil {
            let hosting = NSHostingController(rootView: OfficeWindowRoot(model: model, state: state))
            // Pencere boyutunu içerik belirlemesin (kullanıcı/kayıtlı boyut korunur).
            hosting.sizingOptions = []
            let frame = window.frame
            window.contentViewController = hosting
            window.setFrame(frame, display: false)
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        refreshPanoServices()
    }

    func close() {
        window.close()
    }

    private func saveFrame() {
        // Tam ekranda ekran boyutlu çerçeve kaydedilmez (çıkışta eski çerçeve döner).
        guard isOpen, !state.isFullScreen, !window.styleMask.contains(.fullScreen) else { return }
        defaults.set(OfficeWindowFrame.encode(window.frame), forKey: OfficeWindowFrame.defaultsKey)
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { saveFrame() }

    // MARK: Tam ekran + pano hizmetleri

    func windowWillEnterFullScreen(_ notification: Notification) {
        state.isFullScreen = true
        lastActivity = .now
        state.stripVisible = true
        installActivityMonitor()
        scheduleHide()
        refreshPanoServices()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        state.isFullScreen = false
        state.stripVisible = true
        removeActivityMonitor()
        refreshPanoServices()
    }

    /// Saat (pano etkin + köşe açık + pencere görünür) ve uyanık-tut (ayar + tam ekran + açık) durumlarını eşitler.
    private func refreshPanoServices() {
        let visible = isOpen && window.occlusionState.contains(.visible) && !window.isMiniaturized
        if isOpen, state.panoActive, state.settings.showsClockSummary, visible { state.clock.start() } else { state.clock.stop() }
        keepAwake.update(setting: state.settings.keepAwake, fullScreen: state.isFullScreen, windowOpen: isOpen)
        if isOpen, occlusionObserver == nil {
            occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPanoServices() }
            }
        }
    }

    /// Tam ekranda fare/klavye hareketi: şerit görünür, 3 sn sonra solar; imleç şerit gizliyken gizlenir.
    private func installActivityMonitor() {
        guard activityMonitor == nil else { return }
        window.acceptsMouseMovedEvents = true
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .scrollWheel, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { if event.window === self?.window { self?.noteActivity() } }
            return event
        }
    }

    private func removeActivityMonitor() {
        if let m = activityMonitor { NSEvent.removeMonitor(m) }
        activityMonitor = nil
        hideTimer?.invalidate()
        hideTimer = nil
        window.acceptsMouseMovedEvents = false
    }

    private func noteActivity() {
        guard state.isFullScreen else { return }
        lastActivity = .now
        if !state.stripVisible { state.stripVisible = true }
        scheduleHide()
    }

    /// Tek seferlik zamanlayıcı: son hareketten 3 sn sonra şerit solar ve imleç gizlenir (imleç şerit üzerindeyse şerit kalır).
    private func scheduleHide() {
        hideTimer?.invalidate()
        guard let at = OfficeChromeVisibility.nextHide(fullScreen: state.isFullScreen, now: .now, lastActivity: lastActivity) else { return }
        let t = Timer(fire: at, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateChrome() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        hideTimer = t
    }

    private func evaluateChrome() {
        hideTimer = nil
        guard state.isFullScreen, isOpen else { return }
        let top = window.frame.maxY - NSEvent.mouseLocation.y
        let onStrip = NSMouseInRect(NSEvent.mouseLocation, window.frame, false) && top < 48
        if onStrip { lastActivity = .now; scheduleHide(); return }
        let hidden = OfficeChromeVisibility.cursorHidden(fullScreen: true, now: .now, lastActivity: lastActivity, pointerOnStrip: false)
        state.stripVisible = !hidden
        if hidden { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    func windowWillClose(_ notification: Notification) {
        saveFrame()
        removeActivityMonitor()
        state.isFullScreen = false
        state.stripVisible = true
        state.clock.stop()
        keepAwake.releaseAll()
        if let o = occlusionObserver { NotificationCenter.default.removeObserver(o) }
        occlusionObserver = nil
        // İçeriği hemen bırak (sahne sökülür); pencere nesnesi ve anahtarlar kalır.
        window.contentViewController = nil
        state.selectedRoom = nil
    }
}
