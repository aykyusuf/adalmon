import AppKit

@main
@MainActor
enum AdalmonMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(DockModeController.launchPolicy)
        withExtendedLifetime(delegate) { app.run() }
    }
}
