import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var router: SettingsRouter?
    private var statusBar: StatusBarController?
    private var panel: PanelController?
    private var settings: SettingsWindowController?
    private var mainWindow: MainWindowController?
    private var dockMode: DockModeController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = model.prefs
        let model = model
        let router = SettingsRouter(isDockModeOn: { prefs.showInDock })
        let settings = SettingsWindowController(model: model, router: router)
        let mainWindow = MainWindowController(model: model, router: router)
        router.attach(showMainWindow: { mainWindow.show() }, showSettingsWindow: { settings.show() })
        let panel = PanelController(
            model: model,
            openApp: { prefs.showInDock ? mainWindow.show() : router.open() },
            openSettings: { router.open() }
        )
        let dockMode = DockModeController(
            prefs: prefs,
            makeMenu: { [unowned self] in MainMenuBuilder.make(target: self) },
            closeMainWindow: {
                // Dock modu kapanırken ana pencerede Ayarlar açıksa, ayrı Ayarlar penceresine geç.
                let showingSettings = mainWindow.isOpen && router.mainSectionIsSettings
                mainWindow.close()
                if showingSettings { settings.show() }
            },
            closeSettingsWindow: {
                // Dock modu açılırken ayrı Ayarlar penceresi açıksa, aynı bölümü ana pencerede göster.
                guard settings.isVisible else { return }
                settings.close()
                router.open()
            }
        )
        self.router = router
        self.settings = settings
        self.mainWindow = mainWindow
        self.panel = panel
        self.dockMode = dockMode
        AdalmonIntentHub.backend = LiveIntentBackend(model: model, openRoute: { router.open(route: $0) })
        statusBar = StatusBarController(model: model) { [weak panel] button in panel?.toggle(relativeTo: button) }
        model.start()
        dockMode.start()
        if model.prefs.showInDock { mainWindow.show() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard model.prefs.showInDock else { return true }
        mainWindow?.show()
        return false
    }

    /// `adalmon://battery` vb. (widget dokunuşu, kestirmeler).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let router else { return }
        for url in urls { router.handle(url: url) }
    }

    @objc func openSettings(_ sender: Any?) { router?.open() }
    @objc func showMainWindow(_ sender: Any?) { mainWindow?.show() }
}
