import AppKit
import Observation

/// "Dock'ta göster" ayarına göre uygulamanın etkinleştirme politikasını değiştirir.
/// Açıkken Dock simgesi ve uygulama menüsü vardır (`.regular`); kapalıyken yalnızca menü çubuğu öğesi (`.accessory`).
/// Info.plist'te `LSUIElement` açık kalır; politika çalışma zamanında belirlenir.
@MainActor
final class DockModeController {
    private let prefs: Preferences
    private let makeMenu: @MainActor () -> NSMenu
    private let closeMainWindow: @MainActor () -> Void
    private let closeSettingsWindow: @MainActor () -> Void
    private var observation: Task<Void, Never>?

    /// Açılışta (tercihlerden) kullanılacak politika; Dock simgesi titremesin diye `main()` içinde okunur.
    static var launchPolicy: NSApplication.ActivationPolicy {
        UserDefaults.standard.bool(forKey: "showInDock") ? .regular : .accessory
    }

    init(prefs: Preferences, makeMenu: @escaping @MainActor () -> NSMenu, closeMainWindow: @escaping @MainActor () -> Void,
         closeSettingsWindow: @escaping @MainActor () -> Void) {
        self.prefs = prefs
        self.makeMenu = makeMenu
        self.closeMainWindow = closeMainWindow
        self.closeSettingsWindow = closeSettingsWindow
    }

    /// Mevcut ayarı uygular ve sonraki değişiklikleri canlı izler.
    func start() {
        apply(prefs.showInDock)
        observation = Task { [weak self, prefs] in
            for await show in Observations({ prefs.showInDock }) {
                self?.apply(show)
            }
        }
    }

    func apply(_ show: Bool) {
        if show {
            if NSApp.mainMenu == nil { NSApp.mainMenu = makeMenu() }
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
            }
            // Ayarlar artık ana pencerede; ayrı Ayarlar penceresi açıksa kapanır.
            closeSettingsWindow()
        } else {
            closeMainWindow()
            NSApp.mainMenu = nil
            guard NSApp.activationPolicy() != .accessory else { return }
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate()
        }
    }
}
