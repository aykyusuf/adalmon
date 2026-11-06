import AppKit
import SwiftUI

/// Dock modunun ana penceresi. SwiftUI içeriği yalnızca pencere açıkken vardır: kapanınca hosting controller
/// bırakılır, böylece gizli pencere modeli gözlemlemez ve boşuna yeniden çizilmez (pil).
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let router: SettingsRouter
    private let window: NSWindow

    private static let frameName = "AdalmonMainWindow"
    /// Büyük varsayılan boyut bir kez uygulandı mı? (Önceden kaydedilmiş küçük çerçeve bir kez ezilir, sonra kullanıcıya bırakılır.)
    static let sizedKey = "mainWindow.sizedV2"
    static let minContentSize = NSSize(width: 940, height: 600)

    /// Ekranın görünür alanının ~%85'i (en çok 1600x1050, en az `minContent`; görünür alanı aşmaz), ortalanmış.
    static func defaultFrame(visible: NSRect, minContent: NSSize = minContentSize) -> NSRect {
        let width = min(visible.width, max(minContent.width, min(visible.width * 0.85, 1_600)))
        let height = min(visible.height, max(minContent.height, min(visible.height * 0.85, 1_050)))
        return NSRect(x: (visible.midX - width / 2).rounded(), y: (visible.midY - height / 2).rounded(),
                      width: width.rounded(), height: height.rounded())
    }

    /// Büyük varsayılan çerçeve uygulanmalı mı: kayıtlı çerçeve yoksa ya da V2 geçişi henüz yapılmadıysa.
    static func needsDefaultFrame(restored: Bool, defaults: UserDefaults = .standard) -> Bool {
        !restored || !defaults.bool(forKey: sizedKey)
    }

    init(model: AppModel, router: SettingsRouter) {
        self.model = model
        self.router = router
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        super.init()
        window.title = "Adalmon"
        window.toolbarStyle = .unified
        window.contentMinSize = Self.minContentSize
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName(Self.frameName)
        let restored = window.setFrameUsingName(Self.frameName)
        // Kayıtlı çerçeve yoksa ya da büyük varsayılan henüz uygulanmadıysa ekranı büyük ölçüde dolduran boyutla aç.
        // Bayrak sonrasında kullanıcının yeniden boyutlandırmasına dokunmaz.
        // Testler uygulamayı host olarak başlatır; gerçek kullanıcı ayarlarına/çerçevesine dokunulmaz.
        if !AppEnvironment.isRunningTests, Self.needsDefaultFrame(restored: restored) {
            if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
                window.setFrame(Self.defaultFrame(visible: visible), display: false)
                window.saveFrame(usingName: Self.frameName)
            } else if !restored {
                window.center()
            }
            UserDefaults.standard.set(true, forKey: Self.sizedKey)
        }
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
