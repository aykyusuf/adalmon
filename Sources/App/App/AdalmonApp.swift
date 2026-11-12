import AppKit

@main
@MainActor
enum AdalmonMain {
    static func main() {
        // Tek kopya: aynı paket kimliğiyle daha önce (küçük PID) başlamış bir Adalmon varsa onu öne getir ve çık.
        // İkisi aynı anda açılırsa ikisi de birbirini görür; küçük PID kalır, büyük PID çıkar (ikisi birden kapanmaz).
        if !AppEnvironment.isRunningTests, case .yield(let other) = SingleInstance.claim() {
            other?.activate()
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Test sunucusu Dock'ta/menüde ikinci Adalmon olarak görünmesin.
        app.setActivationPolicy(AppEnvironment.isRunningTests ? .accessory : DockModeController.launchPolicy)
        withExtendedLifetime(delegate) { app.run() }
    }
}
