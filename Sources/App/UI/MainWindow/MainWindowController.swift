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
    /// V3: V2 bayrağı eski çalıştırmalarda küçük çerçeveyi büyütmeden kalmıştı; bu sürüm yeniden dener.
    static let sizedKey = "mainWindow.sizedV3"
    /// Kayıtlı çerçeve bunun altındaysa (genişlik ya da yükseklik) bir kez büyük varsayılana çekilir.
    static let enlargeBelow = NSSize(width: 1_100, height: 750)
    static let minContentSize = NSSize(width: 940, height: 600)

    /// Ekranın görünür alanının ~%85'i (en çok 1600x1050, en az `minContent`; görünür alanı aşmaz), ortalanmış.
    static func defaultFrame(visible: NSRect, minContent: NSSize = minContentSize) -> NSRect {
        let width = min(visible.width, max(minContent.width, min(visible.width * 0.85, 1_600)))
        let height = min(visible.height, max(minContent.height, min(visible.height * 0.85, 1_050)))
        return NSRect(x: (visible.midX - width / 2).rounded(), y: (visible.midY - height / 2).rounded(),
                      width: width.rounded(), height: height.rounded())
    }

    /// Büyük varsayılan çerçeve uygulanmalı mı: kayıtlı çerçeve yoksa ya da (V3 geçişi henüz yapılmadıysa ve) kayıtlı çerçeve
    /// `enlargeBelow`'dan küçükse. Geçiş yapıldıktan sonra kullanıcının boyutu hep korunur.
    static func needsDefaultFrame(restored: Bool, savedSize: NSSize? = nil, defaults: UserDefaults = .standard) -> Bool {
        guard restored else { return true }
        guard !defaults.bool(forKey: sizedKey) else { return false }
        guard let savedSize else { return true }
        return savedSize.width < enlargeBelow.width || savedSize.height < enlargeBelow.height
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
        // Testler uygulamayı host olarak başlatır; gerçek kullanıcının kayıtlı çerçevesine dokunulmasın.
        let restored = !AppEnvironment.isRunningTests && window.setFrameAutosaveName(Self.frameName) && window.setFrameUsingName(Self.frameName)
        // Kayıtlı çerçeve yoksa ya da büyük varsayılan henüz uygulanmadıysa ekranı büyük ölçüde dolduran boyutla aç.
        // Bayrak sonrasında kullanıcının yeniden boyutlandırmasına dokunmaz.
        // Testler uygulamayı host olarak başlatır; gerçek kullanıcı ayarlarına/çerçevesine dokunulmaz.
        if !AppEnvironment.isRunningTests {
            if Self.needsDefaultFrame(restored: restored, savedSize: restored ? window.frame.size : nil) {
                if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
                    window.setFrame(Self.defaultFrame(visible: visible), display: false)
                    window.saveFrame(usingName: Self.frameName)
                } else if !restored {
                    window.center()
                }
            }
            UserDefaults.standard.set(true, forKey: Self.sizedKey)
        }
    }

    /// Pencere çerçevesi (testler için).
    var frame: NSRect {
        get { window.frame }
        set { window.setFrame(newValue, display: false) }
    }

    func show() {
        if window.contentViewController == nil {
            let hosting = NSHostingController(rootView: MainWindowRoot(model: model, router: router))
            // `.minSize` her görünüm güncellemesinde (saniyelik canlı liste, her ölçüm adımı) tüm sayfanın en küçük boyutunu
            // yeniden ölçüyordu (NSHostingView.minSize → tam yerleşim; boşta ana iş parçacığının ~%30'u). En küçük boyut
            // zaten `contentMinSize` ile sabit (pil).
            hosting.sizingOptions = []
            // `contentViewController` atanınca AppKit pencereyi içeriğin tercih ettiği (en küçük) boyuta çeker; her açılışta
            // büyük varsayılan/kullanıcı boyutu böylece 940x652'ye iniyordu. Atamadan önceki çerçeve geri konur.
            let frame = window.frame
            window.contentViewController = hosting
            window.setFrame(frame, display: false)
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
