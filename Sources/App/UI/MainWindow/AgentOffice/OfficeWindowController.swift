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

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
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
        }
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
    }

    func close() {
        window.close()
    }

    private func saveFrame() {
        guard isOpen else { return }
        defaults.set(OfficeWindowFrame.encode(window.frame), forKey: OfficeWindowFrame.defaultsKey)
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { saveFrame() }

    func windowWillClose(_ notification: Notification) {
        saveFrame()
        // İçeriği hemen bırak (sahne sökülür); pencere nesnesi ve anahtarlar kalır.
        window.contentViewController = nil
        state.selectedRoom = nil
    }
}
