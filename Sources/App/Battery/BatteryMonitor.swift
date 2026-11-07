import AppKit
import Foundation
import IOKit.ps
import Observation

struct BatteryEnergyApp: Identifiable, Equatable, Sendable {
    var app: String
    var name: String
    /// Listedeki toplam enerjiye oranı (0...1).
    var share: Double
    var id: String { app }
}

/// Mac pil izleyicisi. Olay tabanlı (IOPSNotificationCreateRunLoopSource) + 60 sn'lik düşük öncelikli zamanlayıcı.
/// Pencere/panel görünürken 5 sn'de bir canlı değer (watt, amper) okunur; gizliyken ek okuma yoktur.
@MainActor @Observable
final class BatteryMonitor {
    static let sampleInterval: TimeInterval = 60
    static let visibleInterval: TimeInterval = 5
    static let flushBatch = 5

    private(set) var reading: BatteryReading?
    var energyApps: [BatteryEnergyApp] = []
    var lastFullCharge: Date?
    var hasBattery: Bool { reading != nil }

    @ObservationIgnored private let store: UsageStore?
    @ObservationIgnored private let readProvider: () -> BatteryReading?
    @ObservationIgnored private let alertConfig: () -> BatteryAlertConfig
    @ObservationIgnored private let notify: (String, String) -> Void
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var engine = BatteryAlertEngine()
    @ObservationIgnored private var energy = BatteryEnergyTracker()
    @ObservationIgnored private var screen = ScreenOnClock(now: .now)
    @ObservationIgnored private var pending: [BatterySample] = []
    @ObservationIgnored private var pendingDeltas: [BatteryEnergyTracker.Delta] = []
    @ObservationIgnored private var pendingScreen: [ScreenOnClock.DaySeconds] = []
    @ObservationIgnored private var temperatureC: Double?
    @ObservationIgnored private var appleMaxCapacity: Int?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var visibleTimer: Timer?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastPlugged: Bool?
    @ObservationIgnored private var lastCharging: Bool?
    @ObservationIgnored private(set) lazy var presenter = BatteryAlertPresenter()
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var isPreview = false

    init(store: UsageStore?, alertConfig: @escaping () -> BatteryAlertConfig = { BatteryAlertConfig() },
         notify: @escaping (String, String) -> Void = { _, _ in }, defaults: UserDefaults = .standard,
         readProvider: @escaping () -> BatteryReading? = { BatteryReader.read() }) {
        self.store = store
        self.alertConfig = alertConfig
        self.notify = notify
        self.defaults = defaults
        self.readProvider = readProvider
    }

    /// Önizleme/test: sabit okuma.
    convenience init(preview reading: BatteryReading?, store: UsageStore? = nil) {
        self.init(store: store, readProvider: { reading })
        self.reading = reading
        isPreview = true
    }

    // MARK: Yaşam döngüsü

    func start() {
        guard !started else { return }
        started = true
        let first = readProvider()
        guard first != nil else { return } // masaüstü Mac: hiçbir şey kurulmaz
        applyHealthCache()
        refresh(isEvent: false, record: true)

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.powerSourceChanged() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            source = src
        }
        let t = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.minuteTick() }
        }
        t.tolerance = 15
        RunLoop.main.add(t, forMode: .common)
        timer = t
        observeSystem()
        Task { [weak self] in
            await self?.store?.batteryMaintenance()
            await self?.refreshHealthIfNeeded()
            await self?.refreshHistoryExtras()
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        visibleTimer?.invalidate(); visibleTimer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
        let center = NSWorkspace.shared.notificationCenter
        for o in observers { center.removeObserver(o); NotificationCenter.default.removeObserver(o) }
        observers = []
        flushNow()
        started = false
    }

    func setTemperature(_ celsius: Double?) {
        guard let celsius else { return }
        if let old = temperatureC, abs(old - celsius) < 0.1 { return }
        temperatureC = celsius
        if var r = reading, r.temperatureC != celsius {
            r.temperatureC = celsius
            reading = r
        }
    }

    /// Panel/ana pencere görünürken canlı güç değerleri için 5 sn'lik okuma; gizlenince durur.
    func setVisible(_ isVisible: Bool) {
        guard isVisible != visible else { return }
        visible = isVisible
        visibleTimer?.invalidate()
        visibleTimer = nil
        guard isVisible, started else { return }
        refresh(isEvent: false, record: false)
        Task { await refreshHistoryExtras() }
        let t = Timer(timeInterval: Self.visibleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(isEvent: false, record: false) }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        visibleTimer = t
    }

    // MARK: Okuma

    private func powerSourceChanged() {
        refresh(isEvent: true, record: false)
    }

    private func minuteTick() {
        refresh(isEvent: false, record: true)
        if visible { Task { await refreshHistoryExtras() } }
        if let h = Optional(BatteryHealthProvider.cached(defaults)), BatteryHealthProvider.needsRefresh(h) {
            Task { await refreshHealthIfNeeded() }
        }
    }

    private func refresh(isEvent: Bool, record: Bool) {
        guard var r = readProvider() else { return }
        r.temperatureC = temperatureC
        r.appleMaxCapacityPercent = appleMaxCapacity
        let stateChanged = (lastPlugged != nil && lastPlugged != r.isPluggedIn) || (lastCharging != nil && lastCharging != r.isCharging)
        lastPlugged = r.isPluggedIn
        lastCharging = r.isCharging

        var comparable = r
        if let old = reading { comparable.timestamp = old.timestamp }
        if comparable != reading { reading = r }

        for event in engine.evaluate(r, config: alertConfig()) { deliver(event) }

        if let delta = energy.consume(level: r.level, day: UsageStore.dayKey(r.timestamp)) { pendingDeltas.append(delta) }
        if record || (isEvent && stateChanged) {
            pending.append(BatterySample(r))
            pendingScreen += screen.flush(at: r.timestamp)
            if pending.count >= Self.flushBatch || stateChanged { flushNow() }
        }
    }

    func flushNow() {
        guard !pending.isEmpty || !pendingDeltas.isEmpty || !pendingScreen.isEmpty else { return }
        let samples = pending, deltas = pendingDeltas, screenSecs = pendingScreen
        pending = []; pendingDeltas = []; pendingScreen = []
        guard let store else { return }
        Task { await store.recordBattery(samples: samples, deltas: deltas, screen: screenSecs) }
    }

    // MARK: Sistem olayları

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        func add(_ name: Notification.Name, center: NotificationCenter = NSWorkspace.shared.notificationCenter,
                 _ body: @escaping @MainActor (BatteryMonitor) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            })
        }
        add(NSWorkspace.screensDidSleepNotification) { $0.setScreen(awake: false) }
        add(NSWorkspace.screensDidWakeNotification) { $0.setScreen(awake: true) }
        add(NSWorkspace.willSleepNotification) { $0.setScreen(awake: false) }
        add(NSWorkspace.didWakeNotification) { m in m.setScreen(awake: true); m.refresh(isEvent: true, record: true) }
        add(NSWorkspace.sessionDidResignActiveNotification) { $0.setSession(active: false) }
        add(NSWorkspace.sessionDidBecomeActiveNotification) { $0.setSession(active: true) }
        add(.NSProcessInfoPowerStateDidChange, center: .default) { $0.refresh(isEvent: true, record: false) }
        _ = ws
    }

    private func setScreen(awake: Bool) { pendingScreen += screen.update(screensAwake: awake, at: .now) }
    private func setSession(active: Bool) { pendingScreen += screen.update(sessionActive: active, at: .now) }

    // MARK: Uyarılar

    private func deliver(_ event: BatteryAlertEvent) {
        let a = event.action
        if let sound = a.sound { NSSound(named: NSSound.Name(sound))?.play() }
        if a.notification { notify(event.title, event.message) }
        presenter.show(event)
    }

    /// Ayarlardaki "Önizle" düğmeleri.
    func preview(_ event: BatteryAlertEvent) { deliver(event) }

    /// Cihaz (AirPods, iPhone…) uyarıları aynı sunucuyu kullanır: ses, bildirim, balon / kenar parlaması.
    func present(_ event: BatteryAlertEvent) { deliver(event) }

    // MARK: Sağlık ve geçmiş

    private func applyHealthCache() {
        appleMaxCapacity = BatteryHealthProvider.cached(defaults).percent
    }

    private func refreshHealthIfNeeded() async {
        let cached = BatteryHealthProvider.cached(defaults)
        guard BatteryHealthProvider.needsRefresh(cached) else { return }
        let fetched = await BatteryHealthProvider.fetch()
        BatteryHealthProvider.store(percent: fetched, defaults)
        if let fetched {
            appleMaxCapacity = fetched
            if var r = reading { r.appleMaxCapacityPercent = fetched; reading = r }
        }
    }

    func refreshHistoryExtras() async {
        guard let store else { return }
        lastFullCharge = await store.lastFullCharge()
        if isPreview { return }
        let ranks = await store.topConsumers(metric: .energy, window: .hours24, limit: 15)
        let total = ranks.reduce(0) { $0 + $1.value }
        guard total > 0 else { energyApps = []; return }
        let apps = ranks.prefix(5).map {
            BatteryEnergyApp(app: $0.app, name: AppCatalog.shared.name(for: $0.app), share: $0.value / total)
        }
        if apps != energyApps { energyApps = apps }
    }
}
