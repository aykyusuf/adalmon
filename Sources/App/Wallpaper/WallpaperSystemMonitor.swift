import AppKit
import Foundation
import IOKit.ps

/// Sistem durumu girdileri (pil, Düşük Güç, kilit, ekran uykusu…). Yalnızca olay tabanlı: zamanlayıcı YOK.
/// `start()` çağrılmadıkça hiçbir gözlemci kayıtlı değildir (özellik kapalıyken sıfır maliyet).
@MainActor
final class WallpaperSystemMonitor {
    struct State: Equatable, Sendable {
        var onBattery = false
        var lowPower = false
        /// Oturum kilitli (com.apple.screenIsLocked) ya da hızlı kullanıcı değişimiyle oturum etkin değil.
        var locked = false
        var screenSaver = false
        var displayAsleep = false
    }

    /// Testlerde doğrudan atanabilir.
    var state = State()
    var onChange: (() -> Void)?

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?
    private var sessionInactive = false
    private var screenLocked = false

    var isStarted: Bool { !observers.isEmpty || powerSource != nil }

    func start() {
        guard !isStarted else { return }
        refreshPower()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<WallpaperSystemMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.powerChanged() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSource = src
        }
        func add(_ name: Notification.Name, _ center: NotificationCenter = NSWorkspace.shared.notificationCenter,
                 _ body: @escaping @MainActor (WallpaperSystemMonitor) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self); self.onChange?() } }
            }
            observers.append((center, token))
        }
        add(.NSProcessInfoPowerStateDidChange, .default) { $0.powerChanged(notify: false) }
        add(NSWorkspace.screensDidSleepNotification) { $0.state.displayAsleep = true }
        add(NSWorkspace.screensDidWakeNotification) { $0.state.displayAsleep = false }
        add(NSWorkspace.willSleepNotification) { $0.state.displayAsleep = true }
        add(NSWorkspace.didWakeNotification) { $0.state.displayAsleep = false; $0.powerChanged(notify: false) }
        add(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true; $0.recomputeLock() }
        add(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false; $0.recomputeLock() }
        let dist = DistributedNotificationCenter.default()
        add(.init("com.apple.screenIsLocked"), dist) { $0.screenLocked = true; $0.recomputeLock() }
        add(.init("com.apple.screenIsUnlocked"), dist) { $0.screenLocked = false; $0.recomputeLock() }
        add(.init("com.apple.screensaver.didstart"), dist) { $0.state.screenSaver = true }
        add(.init("com.apple.screensaver.didstop"), dist) { $0.state.screenSaver = false }
    }

    func stop() {
        for o in observers { o.center.removeObserver(o.token) }
        observers = []
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        state = State()
        sessionInactive = false
        screenLocked = false
    }

    private func recomputeLock() { state.locked = screenLocked || sessionInactive }

    private func powerChanged(notify: Bool = true) {
        refreshPower()
        if notify { onChange?() }
    }

    private func refreshPower() {
        let s = PowerState.current()
        state.onBattery = s.onBattery
        state.lowPower = s.lowPowerMode
    }

    /// Ekran koruyucu da "görünmüyor" sayılır: politikanın `locked` girdisine katılır.
    var policyLocked: Bool { state.locked || state.screenSaver }
}
