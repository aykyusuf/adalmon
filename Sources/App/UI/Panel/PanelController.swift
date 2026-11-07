import AppKit
import SwiftUI

/// Menü çubuğu öğesinin altında açılan Liquid Glass panel. Dışarı tıklayınca veya Esc ile kapanır;
/// durum öğesine yeniden tıklamak da kapatır. Yüksekliği ekranın görünür alanını aşmaz (içerik kaydırılır).
///
/// Pil için: SwiftUI içeriği yalnızca panel açıkken var. Kapanınca hosting view atılır,
/// böylece gizli panel modeli gözlemlemez ve saniyede bir yeniden çizilmez.
@MainActor
final class PanelController {
    private let panel: PanelWindow
    private let glass = NSGlassEffectView()
    private let model: AppModel
    private let openApp: () -> Void
    private let openSettings: () -> Void
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    /// Paneli açan durum öğesinin ekran dikdörtgeni; bu alandaki tıklamayı dış-tıklama sayma (aç/kapa `toggle` yapar).
    private var anchorFrame: NSRect = .zero
    /// Panelin alabileceği en büyük yükseklik (açılışta ekrana göre hesaplanır).
    private var maxHeight: CGFloat = 640

    /// Ekran kenarı ve durum çubuğu ile panel arasındaki boşluk.
    private static let screenMargin: CGFloat = 12
    private static let gapBelowButton: CGFloat = 6

    /// Düğmenin altında panelin sığabileceği en büyük yükseklik.
    static func availableHeight(buttonMinY: CGFloat, visible: NSRect) -> CGFloat {
        max(240, min(buttonMinY - gapBelowButton - visible.minY - screenMargin, visible.height - 2 * screenMargin))
    }

    init(model: AppModel, openApp: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.model = model
        self.openApp = openApp
        self.openSettings = openSettings
        panel = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: 372, height: 600),
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
        glass.cornerRadius = 18
        panel.contentView = glass
        panel.onCancel = { [weak self] in self?.close() }
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        panel.isVisible ? close() : show(relativeTo: button)
    }

    private func show(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        anchorFrame = buttonFrame
        maxHeight = Self.availableHeight(buttonMinY: buttonFrame.minY, visible: screen)
        let host = NSHostingView(rootView: PanelView(model: model, openApp: { [weak self] in
            self?.close()
            self?.openApp()
        }, openSettings: { [weak self] in
            self?.close()
            self?.openSettings()
        }, maxHeight: maxHeight, onSizeChange: { [weak self] size in self?.resize(to: size) }))
        host.autoresizingMask = [.width, .height]
        glass.contentView = host
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        if size.width < 100 || size.height < 100 { size = NSSize(width: 372, height: 640) }
        size.height = min(size.height, maxHeight)

        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        let y = buttonFrame.minY - size.height - Self.gapBelowButton
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        model.panelVisible = true

        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self else { return }
                // Durum öğesine tıklama kapatmayı `toggle` yapar; burada da kapatılırsa düğme eylemi paneli yeniden açardı.
                if self.anchorFrame.insetBy(dx: -2, dy: -2).contains(location) { return }
                self.close()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil } // Esc
            return event
        }
    }

    /// İçerik büyüyüp küçülünce paneli üst kenarı sabit kalacak şekilde yeniden boyutlandır.
    private func resize(to size: CGSize) {
        let height = min(size.height, maxHeight)
        guard panel.isVisible, height > 50, abs(panel.frame.height - height) > 1 else { return }
        var f = panel.frame
        let top = f.maxY
        f.size.height = height
        f.origin.y = top - height
        panel.setFrame(f, display: true, animate: false)
    }

    private func close() {
        panel.orderOut(nil)
        glass.contentView = nil
        model.panelVisible = false
        if let m = outsideMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        outsideMonitor = nil
        localMonitor = nil
    }
}
