import AppKit

/// Panelden tetiklenen eylemler. Testte ve ayar önizlemesinde boş bırakılabilir.
struct PanelActions {
    var setBlocked: @MainActor (_ app: String, _ blocked: Bool) -> Void
    var undoToast: @MainActor () -> Void
    var resetConnections: @MainActor (_ app: String) -> Void
    var restartApp: @MainActor (_ app: String) -> Void
    var installFilter: @MainActor () -> Void
    var openApp: @MainActor () -> Void
    var openSettings: @MainActor () -> Void
    var quit: @MainActor () -> Void
    /// Metrik panelleri: Dock modunda Süreçler sayfasını (sekme ile), değilse Etkinlik Monitörü'nü açar.
    var openProcesses: @MainActor (_ tab: ProcessesTab) -> Void = { _ in }
    var openActivityMonitor: @MainActor () -> Void = {}
    var openRoute: @MainActor (_ route: AdalmonRoute) -> Void = { _ in }
    /// "Birleşik görünüm" bağlantısı.
    var showCombined: @MainActor () -> Void = {}
    var refreshBattery: @MainActor () -> Void = {}
    var setLowPowerMode: @MainActor (_ on: Bool) -> Void = { _ in }
    /// Cihaz pilini menü çubuğuna ekler / çıkarır (kimlik, ad, sabitle).
    var setDevicePinned: @MainActor (_ id: String, _ name: String, _ pinned: Bool) -> Void = { _, _, _ in }

    /// Hiçbir şey yapmayan eylemler (önizleme/test).
    static var inert: PanelActions {
        PanelActions(setBlocked: { _, _ in }, undoToast: {}, resetConnections: { _ in }, restartApp: { _ in }, installFilter: {}, openApp: {}, openSettings: {}, quit: {})
    }
}

extension PanelActions {
    @MainActor
    init(model: AppModel, openApp: @escaping @MainActor () -> Void, openSettings: @escaping @MainActor () -> Void) {
        self.init(
            setBlocked: { [weak model] app, blocked in model?.setBlocked(app, blocked) },
            undoToast: { [weak model] in model?.undoToast() },
            resetConnections: { [weak model] app in model?.resetConnections(for: app) },
            restartApp: { [weak model] app in model?.restartApp(app) },
            installFilter: { [weak model] in model?.installer.install() },
            openApp: openApp,
            openSettings: openSettings,
            quit: { NSApp.terminate(nil) }
        )
    }
}
