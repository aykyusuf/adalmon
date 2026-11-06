import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private let router: SettingsRouter
    private var window: NSWindow?

    init(model: AppModel, router: SettingsRouter) {
        self.model = model
        self.router = router
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model, router: router))
            hosting.sizingOptions = [.minSize]
            let w = NSWindow(contentViewController: hosting)
            w.title = "Adalmon Ayarları"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.contentMinSize = NSSize(width: 760, height: 560)
            w.setContentSize(NSSize(width: 880, height: 680))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
