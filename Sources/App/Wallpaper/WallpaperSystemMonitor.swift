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
        /// Çekirdek bellek basıncı kritik (uyarı seviyesi DEĞİL).
        var memoryCritical = false
        /// Isıl durum serious / critical.
        var thermalSerious = false
    }

    /// Testlerde doğrudan atanabilir.
    var state = State()
    var onChange: (() -> Void)?

    /// Sistem okuyucuları (testte değiştirilebilir). Bellek: sysctl kern.memorystatus_vm_pressure_level (1/2/4).
    let memoryLevelReader: () -> Int32?
    let thermalReader: () -> ProcessInfo.ThermalState
    /// Kritik bellek olayından sonra seviye bu kadar sn sonra sysctl ile yeniden okunur (tek seferlik; hâlâ kritikse yeniden kurulur).
    var memoryRecheckDelay: TimeInterval = 20

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?
    private var memorySource: (any DispatchSourceMemoryPressure)?
    private var memoryRecheck: DispatchWorkItem?
    private var sessionInactive = false
    private var screenLocked = false

    init(memoryLevelReader: @escaping () -> Int32? = { Sysctl.int32("kern.memorystatus_vm_pressure_level") },
         thermalReader: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }) {
        self.memoryLevelReader = memoryLevelReader
        self.thermalReader = thermalReader
    }

    var isStarted: Bool { !observers.isEmpty || powerSource != nil || memorySource != nil }

    func start() {
        guard !isStarted else { return }
        refreshPower()
        refreshThermal()
        // Bellek basıncı: olay tabanlı kaynak (yoklama yok). Yalnızca duvar kâğıdı açıkken (start/stop) yaşar.
        let mem = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        mem.setEventHandler { [weak self, weak mem] in
            guard let mem else { return }
            let event = mem.data
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.refreshMemory(event: event) { self.onChange?() }
            }
        }
        memorySource = mem
        mem.activate()
        refreshMemory(event: nil)   // kaynak yalnızca değişimde tetiklenir: başlangıç seviyesi bir kez okunur
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
        // Isıl durum: bildirim herhangi bir iş parçacığından gelebilir; .main kuyruğunda ele alınır.
        add(ProcessInfo.thermalStateDidChangeNotification, .default) { $0.refreshThermal() }
    }

    func stop() {
        for o in observers { o.center.removeObserver(o.token) }
        observers = []
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        memorySource?.cancel()
        memorySource = nil
        memoryRecheck?.cancel()
        memoryRecheck = nil
        state = State()
        sessionInactive = false
        screenLocked = false
    }

    private func refreshThermal() { state.thermalSerious = WallpaperPolicy.isThermalSerious(thermalReader()) }

    /// Bellek seviyesini günceller; değiştiyse true. Doğruluk kaynağı sysctl'dir; okunamazsa olay maskesine düşülür.
    /// Kritikteyken tek seferlik bir yeniden okuma kurulur (normal olayı kaçarsa da devam edebilsin); zamanlayıcı sürekli değildir.
    @discardableResult
    func refreshMemory(event: DispatchSource.MemoryPressureEvent?) -> Bool {
        let before = state.memoryCritical
        if let level = memoryLevelReader() {
            state.memoryCritical = WallpaperPolicy.isMemoryCritical(sysctlLevel: level)
        } else if let event {
            state.memoryCritical = event.contains(.critical)
        }
        memoryRecheck?.cancel()
        memoryRecheck = nil
        if state.memoryCritical, memorySource != nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.memorySource != nil else { return }
                    if self.refreshMemory(event: nil) { self.onChange?() }
                }
            }
            memoryRecheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + memoryRecheckDelay, execute: work)
        }
        return before != state.memoryCritical
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
