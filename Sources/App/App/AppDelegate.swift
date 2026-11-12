import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var router: SettingsRouter?
    private var statusBar: StatusBarController?
    private var panel: PanelController?
    private var settings: SettingsWindowController?
    private var mainWindow: MainWindowController?
    private var officeWindow: OfficeWindowController?
    private var dockMode: DockModeController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = model.prefs
        let model = model
        let router = SettingsRouter(isDockModeOn: { prefs.showInDock })
        let settings = SettingsWindowController(model: model, router: router)
        let mainWindow = MainWindowController(model: model, router: router)
        let officeWindow = OfficeWindowController(model: model)
        router.attach(showMainWindow: { mainWindow.show() }, showSettingsWindow: { settings.show() },
                      showOfficeWindow: { officeWindow.show() })
        model.alerts.openFilterSettings = { router.open(.filter) }
        let panel = PanelController(
            model: model,
            openApp: { prefs.showInDock ? mainWindow.show() : router.open() },
            openSettings: { router.open() },
            openRoute: { router.open(route: $0) },
            openProcesses: { tab in
                // Dock modunda Süreçler sayfası (sekme ile); değilse Etkinlik Monitörü.
                if prefs.showInDock {
                    router.processesTab = tab
                    router.open(route: .processes)
                } else {
                    PanelController.openActivityMonitor()
                }
            }
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
        self.officeWindow = officeWindow
        self.panel = panel
        self.dockMode = dockMode
        AdalmonIntentHub.backend = LiveIntentBackend(model: model, openRoute: { router.open(route: $0) })
        let statusBar = StatusBarController(model: model) { [weak panel] button, route in panel?.click(on: button, route: route) }
        panel.statusItemFrames = { [weak statusBar] in statusBar?.buttonFrames() ?? [] }
        model.statusItemPositions = { [weak statusBar] in statusBar?.itemPositions() ?? [:] }
        self.statusBar = statusBar
        model.start()
        dockMode.start()
        if !AppEnvironment.isRunningTests {
            WallpaperService.shared.start() // ana şalter kapalıysa hiçbir şey yapmaz
            // CPU kuralı mevcut metrik ölçümünü kullanır (yeni zamanlayıcı yok); duvar kâğıdı kapalıysa anında döner.
            let wallpaper = WallpaperService.shared.controller
            // Ofis duvar kâğıdı kaynağı: canlı ajan oturumları + özellik anahtarı (okunan @Observable alanlar izlenir).
            wallpaper.officeFeed = OfficeWallpaperFeed(snapshot: {
                OfficeFeedSnapshot(members: OfficeMember.members(from: model.agents.monitor.dock.open), agentsEnabled: model.prefs.agentsEnabled)
            }, setShellObserved: { observed in
                if observed { model.agents.monitor.addShellObserver() } else { model.agents.monitor.removeShellObserver() }
            })
            model.onSnapshot = { [weak wallpaper] in wallpaper?.ingestCPU($0.cpu.total) }
        }
        if !AppEnvironment.isRunningTests { SaverService.shared.launchCheck(wallpaper: .shared) } // kuruluysa paketi/videoları güncel tutar
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
    @objc func showOfficeWindow(_ sender: Any?) { officeWindow?.show() }
}
