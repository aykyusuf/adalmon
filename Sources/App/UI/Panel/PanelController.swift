import AppKit
import SwiftUI

/// Menü çubuğu öğesinin altında açılan Liquid Glass panel. Tek pencere ve tek `NSHostingView`; içerik türü
/// (CPU, GPU, Bellek, Disk, Ağ, Sıcaklık, Pil ya da Birleşik) `PanelSession` ile değişir. Dışarı tıklayınca veya Esc ile kapanır;
/// aynı öğeye yeniden tıklamak kapatır, başka öğeye tıklamak içeriği titremeden değiştirir. Yüksekliği ekranın görünür alanını aşmaz.
///
/// Pil için: SwiftUI içeriği yalnızca panel açıkken var. Kapanınca hosting view atılır, canlı kaynaklar durdurulur.
@MainActor
final class PanelController {
    private let panel: PanelWindow
    private let glass = NSGlassEffectView()
    /// Pencere içeriği: cam modda `glass`, opak modda doğrudan hosting view bunun içindedir.
    private let root = NSView()
    private let model: AppModel
    private let session = PanelSession()
    private let live: PanelLiveSources
    private let openApp: () -> Void
    private let openSettings: () -> Void
    private let openRoute: (AdalmonRoute) -> Void
    private let openProcesses: (ProcessesTab) -> Void
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    /// Açık panelin öğe/içerik kimliği; nil = kapalı.
    private(set) var route: PanelRoute?
    /// Paneli açan durum öğesinin ekran dikdörtgeni.
    private var anchorFrame: NSRect = .zero
    /// Tüm menü çubuğu öğelerinin ekran dikdörtgenleri: bunlara tıklama dış-tıklama sayılmaz (öğenin kendi eylemi karar verir).
    var statusItemFrames: () -> [NSRect] = { [] }
    /// Panel açılınca uygulamayı etkinleştirir (Esc yalnızca etkin uygulamanın anahtar penceresine gider). Testte değiştirilir.
    var activateApp: () -> Void = { NSApp.activate() }
    private(set) var didRequestActivation = false

    var isVisible: Bool { panel.isVisible }

    private static let screenMargin: CGFloat = 12
    private static let gapBelowButton: CGFloat = 6

    /// Düğmenin altında panelin sığabileceği en büyük yükseklik.
    static func availableHeight(buttonMinY: CGFloat, visible: NSRect) -> CGFloat {
        max(240, min(buttonMinY - gapBelowButton - visible.minY - screenMargin, visible.height - 2 * screenMargin))
    }

    init(model: AppModel, openApp: @escaping () -> Void, openSettings: @escaping () -> Void,
         openRoute: @escaping (AdalmonRoute) -> Void = { _ in }, openProcesses: @escaping (ProcessesTab) -> Void = { _ in }) {
        self.model = model
        self.live = PanelLiveSources(model: model)
        self.openApp = openApp
        self.openSettings = openSettings
        self.openRoute = openRoute
        self.openProcesses = openProcesses
        panel = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: PanelContent.width, height: 600),
                            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow
        glass.cornerRadius = PanelSurface.cornerRadius
        panel.contentView = root
        panel.onCancel = { [weak self] in self?.close() }
    }

    /// Durum öğesi tıklaması. Açık/kapalı/değiştir kararı `PanelToggle` (saf, testli).
    func click(on button: NSStatusBarButton, route newRoute: PanelRoute) {
        switch PanelToggle.next(current: panel.isVisible ? route : nil, click: newRoute) {
        case .open: show(button: button, route: newRoute)
        case .close: close()
        case .switchTo: switchContent(button: button, route: newRoute)
        }
    }

    private func geometry(for button: NSStatusBarButton) -> (frame: NSRect, screen: NSRect)? {
        guard let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return (frame, window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero)
    }

    private func makeActions() -> PanelActions {
        var a = PanelActions(model: model, openApp: { [weak self] in self?.close(); self?.openApp() },
                             openSettings: { [weak self] in self?.close(); self?.openSettings() })
        a.openRoute = { [weak self] route in self?.close(); self?.openRoute(route) }
        a.openProcesses = { [weak self] tab in self?.close(); self?.openProcesses(tab) }
        a.openActivityMonitor = { [weak self] in self?.close(); Self.openActivityMonitor() }
        a.showCombined = { [weak self] in self?.setKind(.combined) }
        a.refreshBattery = { [weak self] in self?.model.battery.refreshNow() }
        a.setLowPowerMode = { on in Task { await ChargingModel.shared.setLowPowerMode(on) } }
        a.setDevicePinned = { [weak self] id, name, pinned in self?.model.prefs.menuBar.setPinned(device: id, name: name, pinned) }
        return a
    }

    static func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func show(button: NSStatusBarButton, route newRoute: PanelRoute) {
        guard let g = geometry(for: button) else { return }
        anchorFrame = g.frame
        route = newRoute
        // Canlı örnekleyici en başta başlar: ilk veri panel çizilirken hazırlanır.
        live.activate(newRoute.kind)
        loadBatteryExtras(for: newRoute.kind)
        session.maxHeight = Self.availableHeight(buttonMinY: g.frame.minY, visible: g.screen)
        session.kind = newRoute.kind
        session.focusDeviceID = newRoute.focusDeviceID
        model.panelKind = newRoute.kind
        let host = NSHostingView(rootView: PanelRootView(model: model, session: session, live: live, actions: makeActions(),
                                                         onSizeChange: { [weak self] size in self?.resize(to: size) }))
        host.autoresizingMask = [.width, .height]
        mount(host)
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        if size.width < 100 || size.height < 100 { size = NSSize(width: PanelContent.width, height: 640) }
        size.height = min(size.height, session.maxHeight)

        var x = g.frame.midX - size.width / 2
        x = min(max(x, g.screen.minX + 8), g.screen.maxX - size.width - 8)
        let y = g.frame.minY - size.height - Self.gapBelowButton
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
        // Esc yalnızca etkin uygulamanın anahtar penceresine gider: başka uygulama önde iken de çalışması için önce uygulamayı
        // etkinleştir, sonra paneli anahtar yap. Ana pencere (Dock modu) görünürken etkinleştirmek onu öne getirirdi: atlanır.
        if !NSApp.isActive && !model.mainWindowVisible {
            didRequestActivation = true
            activateApp()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        // Etkinleştirme bu turda reddedildiyse (başka uygulama odağı bırakmadı) bir tur sonra yeniden dene.
        if !panel.isKeyWindow {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
                self.activateApp()
                self.panel.makeKey()
            }
        }
        model.panelVisible = true

        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self else { return }
                // Durum öğelerine tıklamayı öğenin düğme eylemi yönetir (kapat/değiştir); burada kapatmak yeniden açılmaya yol açardı.
                if self.statusItemFrames().contains(where: { $0.insetBy(dx: -2, dy: -2).contains(location) }) { return }
                if self.anchorFrame.insetBy(dx: -2, dy: -2).contains(location) { return }
                self.close()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil } // Esc
            return event
        }
    }

    /// Panel açıkken başka öğe/içerik: pencere ve hosting view korunur; yalnızca içerik ve konum değişir.
    private func switchContent(button: NSStatusBarButton, route newRoute: PanelRoute) {
        guard let g = geometry(for: button) else { return }
        anchorFrame = g.frame
        route = newRoute
        session.maxHeight = Self.availableHeight(buttonMinY: g.frame.minY, visible: g.screen)
        session.focusDeviceID = newRoute.focusDeviceID
        setKind(newRoute.kind)
        var f = panel.frame
        let top = g.frame.minY - Self.gapBelowButton
        f.origin.x = min(max(g.frame.midX - f.width / 2, g.screen.minX + 8), g.screen.maxX - f.width - 8)
        f.origin.y = top - f.height
        panel.setFrame(f, display: true, animate: false)
    }

    /// İçerik türünü değiştirir (başlıktaki "Birleşik görünüm" bağlantısı dahil); düğme konumu aynı kalır.
    func setKind(_ kind: PanelKind) {
        session.kind = kind
        model.panelKind = kind
        route?.kind = kind
        live.activate(kind)
        loadBatteryExtras(for: kind)
    }

    /// Pil/birleşik panel açılınca enerji kullanan uygulamalar (24 sa) okunur; panelde iskelet bununla çözülür.
    private func loadBatteryExtras(for kind: PanelKind) {
        guard kind.needsBatterySampling else { return }
        let battery = model.battery
        Task { await battery.refreshHistoryExtras() }
    }

    /// Hosting view'ı pencerenin içeriğine yerleştirir: cam modda `NSGlassEffectView` içine, opakta doğrudan.
    private func mount(_ host: NSView) {
        unmount()
        switch model.prefs.panel.config.background {
        case .glass:
            glass.frame = root.bounds
            glass.autoresizingMask = [.width, .height]
            glass.contentView = host
            root.addSubview(glass)
        case .solid:
            host.frame = root.bounds
            root.addSubview(host)
        }
    }

    private func unmount() {
        glass.contentView = nil
        glass.removeFromSuperview()
        root.subviews.forEach { $0.removeFromSuperview() }
    }

    /// İçerik büyüyüp küçülünce paneli üst kenarı sabit kalacak şekilde yeniden boyutlandır.
    private func resize(to size: CGSize) {
        let height = min(size.height, session.maxHeight)
        guard panel.isVisible, height > 50, abs(panel.frame.height - height) > 1 else { return }
        var f = panel.frame
        let top = f.maxY
        f.size.height = height
        f.origin.y = top - height
        if panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // Kart açılıp kapanırken pencere yüksekliği içeriğin animasyonuyla birlikte yumuşakça değişir.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(f, display: true)
            }
        } else {
            panel.setFrame(f, display: true, animate: false)
        }
        panel.invalidateShadow()
    }

    func close() {
        guard panel.isVisible || route != nil else { return }
        panel.orderOut(nil)
        unmount()
        route = nil
        session.focusDeviceID = nil
        live.activate(nil)
        model.panelVisible = false
        model.panelKind = .combined
        if let m = outsideMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        outsideMonitor = nil
        localMonitor = nil
    }

    /// Testler için: pencereye doğrudan erişim.
    var windowForTesting: NSPanel { panel }
}
