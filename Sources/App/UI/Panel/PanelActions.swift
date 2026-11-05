import AppKit

/// Panelden tetiklenen eylemler. Testte ve ayar önizlemesinde boş bırakılabilir.
struct PanelActions {
    var setBlocked: @MainActor (_ app: String, _ blocked: Bool) -> Void
    var undoToast: @MainActor () -> Void
    var installFilter: @MainActor () -> Void
    var openSettings: @MainActor () -> Void
    var quit: @MainActor () -> Void

    /// Hiçbir şey yapmayan eylemler (önizleme/test).
    static var inert: PanelActions {
        PanelActions(setBlocked: { _, _ in }, undoToast: {}, installFilter: {}, openSettings: {}, quit: {})
    }
}

extension PanelActions {
    @MainActor
    init(model: AppModel, openSettings: @escaping @MainActor () -> Void) {
        self.init(
            setBlocked: { [weak model] app, blocked in model?.setBlocked(app, blocked) },
            undoToast: { [weak model] in model?.undoToast() },
            installFilter: { [weak model] in model?.installer.install() },
            openSettings: openSettings,
            quit: { NSApp.terminate(nil) }
        )
    }
}
