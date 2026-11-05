import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusBar: StatusBarController?
    private var panel: PanelController?
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsWindowController(model: model)
        let panel = PanelController(model: model, openSettings: { settings.show() })
        self.settings = settings
        self.panel = panel
        statusBar = StatusBarController(model: model) { [weak panel] button in panel?.toggle(relativeTo: button) }
        model.start()
    }
}
