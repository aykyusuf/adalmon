import Foundation
import Observation

/// Cihaz pilleri: GATT, HID, AirPods yayını, sistem önbelleği ve iPhone/iPad (libimobiledevice) kaynaklarını birleştirir.
///
/// Pil kuralları: arka planda 5 dk'da bir kısa tur (HID + önbellek + GATT + ~10 sn AirPods taraması), panel/Pil sayfası
/// görünürken 30 sn'de bir (tarama 60 sn'de bir), iPhone/iPad ayrıntıları 10 dk'da bir ve sayfa açılınca isteğe bağlı.
/// Test altında hiçbir canlı kaynak kurulmaz (izin penceresi çıkmaz); testler `ingest…` yöntemlerini kullanır.
@MainActor @Observable
final class DeviceBatteryService {
    static let backgroundInterval: TimeInterval = 300
    static let visibleInterval: TimeInterval = 30
    static let iosInterval: TimeInterval = 600
    static let iosMinGap: TimeInterval = 30
    /// Reklam paketi bu RSSI'dan zayıfsa komşunun kulaklığı sayılır.
    static let minimumAdvertisementRSSI = -72

    enum IOSStatus: Equatable {
        case idle, libraryMissing, searching, noDevice
        case failed(String)
    }

    private(set) var devices: [DeviceBattery] = []
    private(set) var iosDevices: [IOSDeviceDetails] = []
    private(set) var iosStatus: IOSStatus = .idle
    private(set) var bluetoothState: BluetoothBatterySource.State = .unknown
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false

    @ObservationIgnored private let settings: () -> [String: DeviceSettings]
    @ObservationIgnored private let enabled: () -> Bool
    @ObservationIgnored private let includeWifi: () -> Bool
    @ObservationIgnored private let deliver: (BatteryAlertEvent) -> Void
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let probe: any IOSDeviceProbing
    @ObservationIgnored private let readHID: @Sendable () -> [DeviceReading]
    @ObservationIgnored private let readCache: @Sendable () -> SystemBluetoothCache
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var engine = DeviceAlertEngine()
    @ObservationIgnored private var bluetooth: BluetoothBatterySource?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var panelVisible = false
    @ObservationIgnored private var pageVisible = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var lastIOSFetch: Date?
    /// Aynı cihaza iki eşzamanlı lockdown oturumu açılmasın.
    @ObservationIgnored private var iosFetchInFlight = false
    @ObservationIgnored private var observed: [DeviceSource: [DeviceReading]] = [:]
    @ObservationIgnored private var cache = SystemBluetoothCache()
    @ObservationIgnored private var advertisements: [Int: (adv: AppleProximityAdvertisement, rssi: Int, at: Date)] = [:]
    @ObservationIgnored private var remembered: [DeviceBattery] = []

    init(settings: @escaping () -> [String: DeviceSettings] = { [:] }, enabled: @escaping () -> Bool = { true },
         includeWifi: @escaping () -> Bool = { true }, deliver: @escaping (BatteryAlertEvent) -> Void = { _ in },
         defaults: UserDefaults = .standard, probe: (any IOSDeviceProbing)? = nil, live: Bool = !AppEnvironment.isRunningTests,
         readHID: @escaping @Sendable () -> [DeviceReading] = { HIDBatteryReader.read() },
         readCache: @escaping @Sendable () -> SystemBluetoothCache = { SystemBluetoothCache.capture() }) {
        self.settings = settings
        self.enabled = enabled
        self.includeWifi = includeWifi
        self.deliver = deliver
        self.defaults = defaults
        self.live = live
        self.probe = probe ?? (live ? IOSDeviceProbe() : UnavailableProbe())
        self.readHID = readHID
        self.readCache = readCache
        remembered = Self.loadRemembered(defaults)
        iosDevices = Self.loadIOS(defaults)
        devices = DeviceMerger.merge(remembered.map(Self.reading(from:)))
    }

    /// Önizleme/test: sabit liste.
    convenience init(preview devices: [DeviceBattery], ios: [IOSDeviceDetails] = []) {
        self.init(defaults: UserDefaults(suiteName: "adalmon.preview.\(UUID().uuidString)") ?? .standard, live: false)
        self.devices = devices
        self.iosDevices = ios
        self.iosStatus = ios.isEmpty ? .noDevice : .idle
    }

    var visibleDevices: [DeviceBattery] {
        let s = settings()
        return devices.filter { !(s[$0.id]?.hidden ?? false) }
    }

    var hiddenDevices: [DeviceBattery] {
        let s = settings()
        return devices.filter { s[$0.id]?.hidden ?? false }
    }

    func device(id: String) -> DeviceBattery? { devices.first { $0.id == id } }

    /// Kullanıcı iPhone & iPad sekmesini bir kez açtı mı (açtıysa arka plan aramaları serbest).
    static var iosArmed: Bool {
        get { UserDefaults.standard.bool(forKey: "devices.iosArmed") }
        set { UserDefaults.standard.set(newValue, forKey: "devices.iosArmed") }
    }

    // MARK: Yaşam döngüsü

    func start() {
        guard live, !started, enabled() else { return }
        started = true
        refresh(scan: false, includeIOS: true)
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        bluetooth?.stop()
        started = false
    }

    /// Ayar açılıp kapanınca.
    func monitoringChanged() {
        if enabled() { start() } else { stop() }
    }

    /// Menü çubuğu paneli açık mı.
    func setPanelVisible(_ isVisible: Bool) { panelVisible = isVisible; applyVisibility() }
    /// Pil sayfasının Cihazlar / iPhone & iPad sekmesi açık mı.
    func setPageVisible(_ isVisible: Bool) { pageVisible = isVisible; applyVisibility() }

    private func applyVisibility() {
        let isVisible = panelVisible || pageVisible
        guard isVisible != visible else { return }
        visible = isVisible
        guard started else { if isVisible { start() }; return }
        scheduleTimer()
        if isVisible { refresh(scan: true, includeIOS: false) }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = visible ? Self.visibleInterval : Self.backgroundInterval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func timerFired() {
        tick += 1
        // Görünürken tarama her ikinci turda (60 sn); arka planda her turda (5 dk).
        refresh(scan: !visible || tick % 2 == 0, includeIOS: true)
    }

    /// Elle yenile (düğme).
    func refreshNow() {
        guard live else { return }
        refresh(scan: true, includeIOS: true, forceIOS: true)
    }

    /// iPhone & iPad sekmesi açılınca / "Yenile".
    func refreshIOS(force: Bool = false) {
        guard live, enabled() else { return }
        Self.iosArmed = true
        Task { await fetchIOS(force: force) }
    }

    // MARK: Okuma turu

    private func refresh(scan: Bool, includeIOS: Bool, forceIOS: Bool = false) {
        guard enabled(), !isRefreshing else { return }
        isRefreshing = true
        let hid = readHID, cacheReader = readCache
        Task { [weak self] in
            // Ucuz kaynaklar arka plan iş parçacığında: izin gerektirmez.
            async let hidReadings = Task.detached(priority: .utility) { hid() }.value
            async let cacheResult = Task.detached(priority: .utility) { cacheReader() }.value
            let (h, c) = await (hidReadings, cacheResult)
            guard let self else { return }
            self.ingestHID(h, recompute: false)
            self.ingestCache(c, recompute: false)
            self.recompute()
            self.isRefreshing = false
            self.runBluetooth(scan: scan)
            // Yerel ağ izni sorusu bağlamsız çıkmasın: iPhone & iPad sekmesi en az bir kez açılana kadar arka planda aranmaz.
            if includeIOS, forceIOS || Self.iosArmed { await self.fetchIOS(force: forceIOS) }
        }
    }

    private func runBluetooth(scan: Bool) {
        guard live else { return }
        if bluetooth == nil {
            // İzin penceresi yalnızca kullanıcı panel/sayfayı açınca ya da izin zaten verilmişse çıkar.
            guard visible || BluetoothBatterySource.isAuthorized else { return }
            if BluetoothBatterySource.isDenied { bluetoothState = .unauthorized; return }
            bluetooth = BluetoothBatterySource(callbacks: .init(
                state: { [weak self] s in Task { @MainActor in self?.bluetoothState = s } },
                gatt: { [weak self] samples in Task { @MainActor in self?.ingestGATT(samples) } },
                advertisement: { [weak self] adv, rssi in Task { @MainActor in self?.ingestAdvertisement(adv, rssi: rssi) } }))
        }
        bluetooth?.refresh(scan: scan)
    }

    // MARK: Kaynak girişleri (testler de bunları kullanır)

    func ingestHID(_ readings: [DeviceReading], recompute doRecompute: Bool = true) {
        observed[.hid] = readings
        if doRecompute { recompute() }
    }

    func ingestCache(_ new: SystemBluetoothCache, now: Date = .now, recompute doRecompute: Bool = true) {
        cache = new
        observed[.systemCache] = new.readings(now: now)
        if doRecompute { recompute(now: now) }
    }

    func ingestGATT(_ samples: [BluetoothBatterySource.GATTSample], now: Date = .now) {
        observed[.gatt] = samples.map {
            DeviceReading(name: $0.name, kind: DeviceKind.guess(name: $0.name), source: .gatt, observedAt: now, level: $0.level)
        }
        recompute(now: now)
    }

    /// Yakındaki, bu Mac'e eşleşmiş bir kulaklığa ait reklam. Ürün kimliği önbellekteki eşleşmiş cihazla eşleşmeli (komşuyu eler).
    func ingestAdvertisement(_ adv: AppleProximityAdvertisement, rssi: Int, now: Date = .now) {
        guard rssi >= Self.minimumAdvertisementRSSI, cache.entry(productID: adv.productID) != nil else { return }
        if let old = advertisements[adv.productID], now.timeIntervalSince(old.at) < 30, old.rssi > rssi + 8 { return }
        advertisements[adv.productID] = (adv, rssi, now)
        observed[.advertisement] = advertisements.values.compactMap { entry in
            guard let paired = cache.entry(productID: entry.adv.productID) else { return nil }
            let a = entry.adv
            let kind = paired.kind == .other || paired.kind == .headphones ? a.kind : paired.kind
            return DeviceReading(name: paired.name, kind: kind, source: .advertisement, observedAt: entry.at, left: a.left, right: a.right,
                                 caseLevel: a.caseLevel, leftCharging: a.leftCharging, rightCharging: a.rightCharging,
                                 caseCharging: a.caseCharging, isConnected: true)
        }
        recompute(now: now)
    }

    func ingestIOS(_ details: [IOSDeviceDetails], now: Date = .now) {
        iosDevices = details
        Self.storeIOS(details, defaults)
        observed[.lockdown] = details.compactMap { d in
            guard let level = d.level else { return nil }
            return DeviceReading(name: d.name, kind: DeviceKind.guess(name: d.productType.isEmpty ? d.name : d.productType + " " + d.name),
                                 source: .lockdown, observedAt: d.fetchedAt, level: level, isCharging: d.isCharging)
        }
        recompute(now: now)
    }

    // MARK: iPhone / iPad

    private func fetchIOS(force: Bool) async {
        guard enabled(), !iosFetchInFlight else { return }
        iosFetchInFlight = true
        defer { iosFetchInFlight = false }
        guard probe.isAvailable else { iosStatus = live ? .libraryMissing : .idle; return }
        if !force, let last = lastIOSFetch, Date.now.timeIntervalSince(last) < (visible ? Self.iosMinGap : Self.iosInterval) { return }
        lastIOSFetch = .now
        if iosDevices.isEmpty { iosStatus = .searching }
        let probe = self.probe, wifi = includeWifi()
        let result = await Task.detached(priority: .utility) { () -> (details: [IOSDeviceDetails], failure: IOSProbeFailure?, found: Int) in
            let refs = probe.listDevices(includeNetwork: wifi)
            var details: [IOSDeviceDetails] = [], failure: IOSProbeFailure?
            for ref in refs {
                switch probe.fetch(ref) {
                case .success(let d): details.append(d)
                case .failure(let f): failure = f
                }
            }
            return (details, failure, refs.count)
        }.value
        if result.found == 0 {
            iosStatus = .noDevice
            // Cihaz artık yok: eski ayrıntılar "son bilinen" olarak kalır.
            return
        }
        if result.details.isEmpty, let failure = result.failure {
            iosStatus = .failed(failure.message)
            return
        }
        iosStatus = .idle
        // Okunamayan cihazın eski kaydı korunur.
        var merged = Dictionary(uniqueKeysWithValues: iosDevices.map { ($0.udid, $0) })
        for d in result.details { merged[d.udid] = d }
        ingestIOS(merged.values.sorted { $0.name < $1.name })
    }

    // MARK: Birleştirme ve uyarılar

    func recompute(now: Date = .now) {
        var readings = observed.values.flatMap(\.self)
        // Son bilinen cihazlar (bayatlayınca "~ son görülme" ile görünür).
        readings += remembered.map(Self.reading(from:))
        let merged = DeviceMerger.merge(readings, now: now)
        if merged != devices { devices = merged }
        remembered = merged
        Self.storeRemembered(merged, defaults)
        lastUpdated = now
        for event in engine.evaluate(merged, settings: settings()) { deliver(event) }
    }

    nonisolated static func reading(from d: DeviceBattery) -> DeviceReading {
        DeviceReading(name: d.name, kind: d.kind, source: d.sources.first ?? .systemCache, observedAt: d.lastSeen, level: d.level, left: d.left,
                      right: d.right, caseLevel: d.caseLevel, leftCharging: d.leftCharging, rightCharging: d.rightCharging,
                      caseCharging: d.caseCharging, isCharging: d.isCharging, isConnected: false)
    }

    // MARK: Kalıcılık

    private static func loadRemembered(_ d: UserDefaults) -> [DeviceBattery] {
        d.data(forKey: "deviceLastKnown").flatMap { try? JSONDecoder().decode([DeviceBattery].self, from: $0) } ?? []
    }

    private static func storeRemembered(_ list: [DeviceBattery], _ d: UserDefaults) {
        d.set(try? JSONEncoder().encode(list), forKey: "deviceLastKnown")
    }

    private static func loadIOS(_ d: UserDefaults) -> [IOSDeviceDetails] {
        d.data(forKey: "iosDeviceDetails").flatMap { try? JSONDecoder().decode([IOSDeviceDetails].self, from: $0) } ?? []
    }

    private static func storeIOS(_ list: [IOSDeviceDetails], _ d: UserDefaults) {
        d.set(try? JSONEncoder().encode(list), forKey: "iosDeviceDetails")
    }
}

/// Canlı kaynak kurulmayan ortamlar (test, önizleme) için boş sonda.
struct UnavailableProbe: IOSDeviceProbing {
    var isAvailable: Bool { false }
    func listDevices(includeNetwork: Bool) -> [IOSDeviceRef] { [] }
    func fetch(_ ref: IOSDeviceRef) -> Result<IOSDeviceDetails, IOSProbeFailure> { .failure(.libraryMissing) }
}
