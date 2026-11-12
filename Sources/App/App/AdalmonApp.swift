import AppKit

@main
@MainActor
enum AdalmonMain {
    static func main() {
        // Tek kopya: aynı paket kimliğiyle daha önce (küçük PID) başlamış bir Adalmon varsa onu öne getir ve çık.
        // İkisi aynı anda açılırsa ikisi de birbirini görür; küçük PID kalır, büyük PID çıkar (ikisi birden kapanmaz).
        if !AppEnvironment.isRunningTests, let other = SingleInstance.olderInstance() {
            other.activate()
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

enum SingleInstance {
    /// Bu süreçten önce başlamış (daha küçük PID'li) aynı uygulama kopyası.
    static func olderInstance(bundleID: String? = Bundle.main.bundleIdentifier,
                              myPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> NSRunningApplication? {
        guard let bundleID else { return nil }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated && $0.processIdentifier != myPID }
        return pick(otherPIDs: others.map(\.processIdentifier), myPID: myPID).flatMap { pid in others.first { $0.processIdentifier == pid } }
    }

    /// Saf karar: benden küçük PID'li bir kopya varsa onu döndür (en küçüğü).
    static func pick(otherPIDs: [pid_t], myPID: pid_t) -> pid_t? {
        otherPIDs.filter { $0 < myPID }.min()
    }
}
