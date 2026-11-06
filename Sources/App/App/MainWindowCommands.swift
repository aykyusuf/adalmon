import AppKit

/// Menü çubuğu komutlarının hedefi: sayfa geçişi (⌘1…⌘5), arama alanına odaklanma (⌘F).
/// `router` uygulama açılırken `AppDelegate` tarafından verilir; menü Dock modu açıkken vardır.
@MainActor
final class MainWindowCommands: NSObject {
    static let shared = MainWindowCommands()

    weak var router: SettingsRouter?

    /// Menü öğesinin `representedObject`'ini (`MainSection.id`) okuyup o sayfayı açar; pencere kapalıysa önce açar.
    @objc func selectSection(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let section = MainSection(id: id) else { return }
        NSApp.sendAction(#selector(AppDelegate.showMainWindow(_:)), to: nil, from: nil)
        router?.selectedMainSection = section
    }

    /// Penceredeki arama alanına (araç çubuğu ya da içerik) odaklanır.
    @objc func focusSearch(_ sender: Any?) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        if let item = window.toolbar?.items.lazy.compactMap({ $0 as? NSSearchToolbarItem }).first {
            item.beginSearchInteraction()
            return
        }
        if let field = window.contentView.flatMap(Self.firstSearchField) {
            window.makeFirstResponder(field)
        }
    }

    private static func firstSearchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        for sub in view.subviews {
            if let found = firstSearchField(in: sub) { return found }
        }
        return nil
    }
}
