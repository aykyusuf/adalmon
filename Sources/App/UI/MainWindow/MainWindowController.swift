import AppKit
import SwiftUI

/// Dock modunun ana penceresi. SwiftUI içeriği yalnızca pencere açıkken vardır: kapanınca hosting controller
/// bırakılır, böylece gizli pencere modeli gözlemlemez ve boşuna yeniden çizilmez (pil).
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let router: SettingsRouter
    private let window: NSWindow

    init(model: AppModel, router: SettingsRouter) {
        self.model = model
        self.router = router
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        super.init()
        window.title = "Adalmon"
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 940, height: 600)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("AdalmonMainWindow")
        if !window.setFrameUsingName("AdalmonMainWindow") { window.center() }
    }

    func show() {
        if window.contentViewController == nil {
            let hosting = NSHostingController(rootView: MainWindowRoot(model: model, router: router))
            hosting.sizingOptions = [.minSize]
            window.contentViewController = hosting
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        model.mainWindowVisible = true
    }

    func close() {
        window.close()
    }

    /// Pencere açık mı (küçültülmüş veya örtülü olsa bile)? Yalnızca kapatılınca içerik bırakıldığı için içeriğe bakılır.
    var isOpen: Bool { window.contentViewController != nil }

    func windowWillClose(_ notification: Notification) {
        // İçeriği hemen bırak; pencere nesnesi (konumu) kalır.
        window.contentViewController = nil
        model.mainWindowVisible = false
    }

    // Küçültülmüş veya tamamen örtülü pencere kullanıcıya görünmez: 1 sn'lik hızlı örnekleme durur (pil).
    func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }
    func windowDidMiniaturize(_ notification: Notification) { updateVisibility() }
    func windowDidDeminiaturize(_ notification: Notification) { updateVisibility() }

    private func updateVisibility() {
        model.mainWindowVisible = isOpen && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }
}
