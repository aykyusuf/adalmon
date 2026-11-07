import XCTest
@testable import Adalmon

/// Cihaz pilleri: yalnızca sabit veri ve sahte kaynaklar. Gerçek Bluetooth / usbmuxd / libimobiledevice kullanılmaz.
final class DeviceBatteryTests: XCTestCase {
    // MARK: AirPods reklam paketi

    /// 4C 00 | 07 19 | payload(25): 01 | 14 20 (AirPods Pro 2, PID 0x2014) | status | batt | charge+case | lid | color | suffix | 16 bayt şifreli
    private func advertisement(status: UInt8, battery: UInt8, chargeCase: UInt8, lid: UInt8, prefix: UInt8 = 0x01, productLE: [UInt8] = [0x14, 0x20]) -> Data {
        var bytes: [UInt8] = [0x4C, 0x00, 0x07, 0x19, prefix] + productLE + [status, battery, chargeCase, lid, 0x00, 0x00]
        bytes += [UInt8](repeating: 0xAB, count: 16)
        return Data(bytes)
    }

    func testAdvertisementParsesLevelsAndFlags() throws {
        // status 0x2B: bit 0x20 set → flip yok. batt 0x97 → sol = düşük nibble (7) = %70, sağ = yüksek (9) = %90.
        // 0x4A: yüksek nibble 4 = kutu şarj oluyor; düşük nibble 0xA = kutu %100. lid 0x00 → kapak açık.
        let adv = try XCTUnwrap(AppleProximityAdvertisement.parse(manufacturerData: advertisement(status: 0x2B, battery: 0x97, chargeCase: 0x4A, lid: 0x00)))
        XCTAssertEqual(adv.productID, 0x2014)
        XCTAssertEqual(adv.kind, .airPodsPro)
        XCTAssertEqual(adv.left, 70)
        XCTAssertEqual(adv.right, 90)
        XCTAssertEqual(adv.caseLevel, 100)
        XCTAssertFalse(adv.leftCharging)
        XCTAssertFalse(adv.rightCharging)
        XCTAssertTrue(adv.caseCharging)
        XCTAssertTrue(adv.lidOpen)
    }

    func testAdvertisementFlippedSwapsEarsAndChargeBits() throws {
        // status 0x0B: bit 0x20 yok → flip. 0x97: sol = yüksek (9) = %90, sağ = düşük (7) = %70.
        // 0x3F: şarj bayrakları 0b0011 (iki kulak şarjda), kutu 0xF = bilinmiyor. lid bit 0x08 → kapalı.
        let adv = try XCTUnwrap(AppleProximityAdvertisement.parse(manufacturerData: advertisement(status: 0x0B, battery: 0x97, chargeCase: 0x3F, lid: 0x08)))
        XCTAssertEqual(adv.left, 90)
        XCTAssertEqual(adv.right, 70)
        XCTAssertNil(adv.caseLevel)
        XCTAssertTrue(adv.leftCharging)
        XCTAssertTrue(adv.rightCharging)
        XCTAssertFalse(adv.caseCharging)
        XCTAssertFalse(adv.lidOpen)
    }

    func testAdvertisementOnlyOneEarCharging() throws {
        // flip yok; bayrak 0b0001 = sol şarjda.
        let adv = try XCTUnwrap(AppleProximityAdvertisement.parse(manufacturerData: advertisement(status: 0x2B, battery: 0xAA, chargeCase: 0x15, lid: 0x00)))
        XCTAssertTrue(adv.leftCharging)
        XCTAssertFalse(adv.rightCharging)
        XCTAssertEqual(adv.left, 100)
        XCTAssertEqual(adv.caseLevel, 50)
    }

    func testAdvertisementRejectsInvalidData() {
        let good = advertisement(status: 0x2B, battery: 0x97, chargeCase: 0x4A, lid: 0)
        XCTAssertNil(AppleProximityAdvertisement.parse(manufacturerData: Data()))
        XCTAssertNil(AppleProximityAdvertisement.parse(manufacturerData: Data([0x4C, 0x00])))
        // Apple değil (Microsoft 0x0006).
        var notApple = [UInt8](good); notApple[0] = 0x06
        XCTAssertNil(AppleProximityAdvertisement.parse(manufacturerData: Data(notApple)))
        // Başka Continuity tipi (0x10 nearby info).
        var otherType = [UInt8](good); otherType[2] = 0x10
        XCTAssertNil(AppleProximityAdvertisement.parse(manufacturerData: Data(otherType)))
        // Uzunluk gerçek veriden büyük.
        XCTAssertNil(AppleProximityAdvertisement.parse(manufacturerData: Data(good.prefix(12))))
        // Eşleşmemiş ön ek.
        XCTAssertNil(AppleProximityAdvertisement.parse(manufacturerData: advertisement(status: 0x2B, battery: 0x97, chargeCase: 0, lid: 0, prefix: 0x05)))
        // Geçersiz nibble (11…14) → bilinmiyor.
        let odd = AppleProximityAdvertisement.parse(manufacturerData: advertisement(status: 0x2B, battery: 0xB7, chargeCase: 0x0C, lid: 0))
        XCTAssertNil(odd?.right)
        XCTAssertNil(odd?.caseLevel)
        XCTAssertEqual(odd?.left, 70)
    }

    func testAdvertisementSkipsOtherTLVBeforeProximity() throws {
        let tail = [UInt8](advertisement(status: 0x2B, battery: 0x55, chargeCase: 0x05, lid: 0)).dropFirst(2)
        let data = Data([0x4C, 0x00, 0x09, 0x02, 0xAA, 0xBB] + tail)
        XCTAssertEqual(AppleProximityAdvertisement.parse(manufacturerData: data)?.left, 50)
    }

    func testProductIDMapping() {
        XCTAssertEqual(AppleProximityAdvertisement.kind(forProductID: 0x200E), .airPodsPro)
        XCTAssertEqual(AppleProximityAdvertisement.kind(forProductID: 0x200A), .airPodsMax)
        XCTAssertEqual(AppleProximityAdvertisement.kind(forProductID: 0x2013), .airPods)
        XCTAssertEqual(AppleProximityAdvertisement.kind(forProductID: 0x9999), .headphones)
    }

    // MARK: GATT / HID

    func testGATTBatteryLevel() {
        XCTAssertEqual(GATTBattery.parseLevel(Data([79])), 79)
        XCTAssertEqual(GATTBattery.parseLevel(Data([0])), 0)
        XCTAssertEqual(GATTBattery.parseLevel(Data([100])), 100)
        XCTAssertNil(GATTBattery.parseLevel(Data([101])))
        XCTAssertNil(GATTBattery.parseLevel(Data([0xFF])))
        XCTAssertNil(GATTBattery.parseLevel(Data()))
    }

    func testHIDBatteryParsing() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let props: [String: Any] = ["BatteryPercent": 18, "Product": "Magic Keyboard with Touch ID", "DeviceAddress": "00-00-00-00-00-00",
                                    "BatteryStatusFlags": 3, "Transport": "Bluetooth"]
        let r = try XCTUnwrap(HIDBatteryParser.reading(from: props, now: now))
        XCTAssertEqual(r.level, 18)
        XCTAssertEqual(r.kind, .keyboard)
        XCTAssertEqual(r.source, .hid)
        XCTAssertTrue(r.isCharging)
        XCTAssertEqual(r.observedAt, now)
        let mouse = try XCTUnwrap(HIDBatteryParser.reading(from: ["BatteryPercent": 64, "Product": "Magic Mouse"]))
        XCTAssertEqual(mouse.kind, .mouse)
        XCTAssertFalse(mouse.isCharging)
        XCTAssertNil(HIDBatteryParser.reading(from: ["Product": "Magic Mouse"]))
        XCTAssertNil(HIDBatteryParser.reading(from: ["BatteryPercent": 140, "Product": "Magic Mouse"]))
        XCTAssertNil(HIDBatteryParser.reading(from: ["BatteryPercent": 50]))
    }

    // MARK: system_profiler

    /// Gerçek çıktının biçimi; adresler ve seri numaraları temizlendi.
    static let profilerJSON = """
    {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
    "device_connected":[
      {"Yusuf iPad":{"device_address":"00:00:00:00:00:01","device_rssi":"-23","device_services":"0x400000 < BLE >"}},
      {"Yusuf’s AirPods Pro ":{"device_address":"00:00:00:00:00:02","device_batteryLevelCase":"72%","device_batteryLevelLeft":"75%","device_batteryLevelRight":"74%",
        "device_minorType":"Headphones","device_productID":"0x2014","device_vendorID":"0x004C"}}],
    "device_not_connected":[
      {"Orochi V2":{"device_address":"00:00:00:00:00:03","device_batteryLevelMain":"92%","device_minorType":"Mouse","device_productID":"0x0095","device_vendorID":"0x1532"}},
      {"Keychron K10 HE":{"device_address":"00:00:00:00:00:04","device_minorType":"Keyboard","device_productID":"0x0EA1"}}]}]}
    """

    func testSystemProfilerParsing() throws {
        let cache = SystemBluetoothCache.parse(json: Data(Self.profilerJSON.utf8))
        XCTAssertEqual(cache.entries.count, 4)
        let pods = try XCTUnwrap(cache.entry(productID: 0x2014))
        XCTAssertEqual(pods.name, "Yusuf’s AirPods Pro")
        XCTAssertEqual(pods.kind, .airPodsPro)
        XCTAssertEqual([pods.left, pods.right, pods.caseLevel], [75, 74, 72])
        XCTAssertTrue(pods.connected)
        let mouse = try XCTUnwrap(cache.entries.first { $0.name == "Orochi V2" })
        XCTAssertEqual(mouse.level, 92)
        XCTAssertEqual(mouse.kind, .mouse)
        XCTAssertFalse(mouse.connected)
        // Pil bilgisi olmayanlar (iPad, klavye) okuma üretmez.
        XCTAssertEqual(Set(cache.readings().map(\.name)), ["Yusuf’s AirPods Pro", "Orochi V2"])
        XCTAssertTrue(cache.readings().allSatisfy { $0.source == .systemCache })
        XCTAssertTrue(SystemBluetoothCache.parse(json: Data("{".utf8)).entries.isEmpty)
        XCTAssertEqual(SystemBluetoothCache.hex("0x2014"), 0x2014)
    }

    // MARK: Birleştirme

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(_ name: String, _ source: DeviceSource, level: Int? = nil, age: TimeInterval = 0, kind: DeviceKind = .other) -> DeviceReading {
        DeviceReading(name: name, kind: kind, source: source, observedAt: now.addingTimeInterval(-age), level: level)
    }

    func testMergePrefersFreshHigherPrioritySource() throws {
        let merged = DeviceMerger.merge([reading("Yusuf iPhone", .gatt, level: 79, kind: .iPhone),
                                         reading("Yusuf iPhone ", .lockdown, level: 78, kind: .iPhone),
                                         reading("yusuf iphone", .systemCache, level: 60)], now: now)
        XCTAssertEqual(merged.count, 1)
        let d = try XCTUnwrap(merged.first)
        XCTAssertEqual(d.level, 78, "lockdown en yüksek öncelik")
        XCTAssertFalse(d.isApproximate)
        XCTAssertFalse(d.isStale)
        XCTAssertEqual(d.sources, [.lockdown, .gatt, .systemCache])
        XCTAssertTrue(d.isConnected)
    }

    func testStaleReadingIsApproximateWithLastSeen() throws {
        let merged = DeviceMerger.merge([reading("Magic Mouse", .hid, level: 40, age: 1_800, kind: .mouse)], now: now)
        let d = try XCTUnwrap(merged.first)
        XCTAssertTrue(d.isStale)
        XCTAssertTrue(d.isApproximate)
        XCTAssertFalse(d.isConnected)
        XCTAssertEqual(d.levelText, "~%40")
        XCTAssertEqual(d.lastSeenText(now: now), "30 dk önce")
        XCTAssertEqual(d.lastSeen, now.addingTimeInterval(-1_800))
    }

    func testFreshLowPriorityBeatsStaleHighPriority() throws {
        let merged = DeviceMerger.merge([reading("X", .gatt, level: 10, age: 7_200), reading("X", .advertisement, level: nil)], now: now)
        XCTAssertTrue(merged.isEmpty || merged.first?.level == 10)
        var pods = reading("AirPods Pro", .advertisement, kind: .airPodsPro)
        pods.left = 80; pods.right = 70; pods.caseLevel = 50
        let m2 = DeviceMerger.merge([pods, reading("AirPods Pro", .systemCache, level: 99)], now: now)
        let d = try XCTUnwrap(m2.first)
        XCTAssertEqual(d.left, 80)
        XCTAssertEqual(d.summaryLevel, 70, "kulaklıkta düşük kulak")
        XCTAssertTrue(d.isApproximate, "reklam adımlı/yaklaşık")
    }

    func testPodsFilledFromCacheMarkedApproximate() throws {
        var live = reading("Pods", .advertisement, kind: .airPodsPro)
        live.left = 80; live.right = 80
        var cache = reading("Pods", .systemCache, kind: .airPodsPro)
        cache.caseLevel = 33
        let d = try XCTUnwrap(DeviceMerger.merge([live, cache], now: now).first)
        XCTAssertEqual(d.caseLevel, 33)
        XCTAssertTrue(d.isApproximate)
    }

    func testMergeSortsLowestFirstAndDropsForgotten() {
        let merged = DeviceMerger.merge([reading("A", .gatt, level: 80), reading("B", .gatt, level: 15), reading("C", .gatt, level: 50),
                                         reading("Old", .hid, level: 5, age: 8 * 86_400)], now: now)
        XCTAssertEqual(merged.map(\.name), ["B", "C", "A"])
        XCTAssertTrue(DeviceMerger.merge([DeviceReading(name: "", kind: .other, source: .gatt, observedAt: now, level: 5),
                                          DeviceReading(name: "NoLevel", kind: .other, source: .gatt, observedAt: now)], now: now).isEmpty)
    }

    func testIdentityNormalizesApostropheAndCase() {
        XCTAssertEqual(DeviceMerger.identity("Yusuf’s AirPods Pro "), DeviceMerger.identity("yusuf's airpods pro"))
    }

    // MARK: Servis (sahte kaynaklar)

    @MainActor
    func testServiceMergesSourcesAndMatchesAdvertisementToPairedDevice() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "adalmon.test.\(UUID().uuidString)"))
        let service = DeviceBatteryService(defaults: defaults, live: false)
        service.ingestCache(SystemBluetoothCache.parse(json: Data(Self.profilerJSON.utf8)), now: now)
        service.ingestGATT([.init(name: "Yusuf iPhone", level: 79)], now: now)
        let adv = try XCTUnwrap(AppleProximityAdvertisement.parse(manufacturerData: advertisement(status: 0x2B, battery: 0x97, chargeCase: 0x4A, lid: 0)))
        service.ingestAdvertisement(adv, rssi: -85, now: now)   // çok zayıf: komşu olabilir
        XCTAssertEqual(service.devices.first { $0.kind == .airPodsPro }?.left, 75, "zayıf reklam yok sayılır, önbellek kalır")
        service.ingestAdvertisement(adv, rssi: -50, now: now)
        let pods = try XCTUnwrap(service.devices.first { $0.kind == .airPodsPro })
        XCTAssertEqual(pods.name, "Yusuf’s AirPods Pro")
        XCTAssertEqual(pods.left, 70)
        XCTAssertEqual(pods.right, 90)
        XCTAssertEqual(pods.caseLevel, 100)
        XCTAssertTrue(pods.caseCharging)
        XCTAssertTrue(pods.isApproximate)
        XCTAssertEqual(service.devices.first?.name, "Yusuf’s AirPods Pro", "en düşük (%70) üstte")
        XCTAssertEqual(service.devices.first { $0.kind == .iPhone }?.level, 79)
        // Eşleşmemiş (komşu) kulaklık ürün kimliği → yok sayılır.
        let foreign = try XCTUnwrap(AppleProximityAdvertisement.parse(manufacturerData: advertisement(status: 0x2B, battery: 0x11, chargeCase: 0x11, lid: 0, productLE: [0x0A, 0x20])))
        service.ingestAdvertisement(foreign, rssi: -40, now: now)
        XCTAssertNil(service.devices.first { $0.kind == .airPodsMax })
        // Yeniden başlatma: son bilinen cihazlar korunur.
        let again = DeviceBatteryService(defaults: defaults, live: false)
        XCTAssertEqual(Set(again.devices.map(\.name)), Set(service.devices.map(\.name)))
    }

    @MainActor
    func testServiceHidesDevicesPerSettings() throws {
        var s = DeviceSettings(); s.hidden = true
        let service = DeviceBatteryService(settings: { ["yusuf ipad": s] }, defaults: try XCTUnwrap(UserDefaults(suiteName: "adalmon.test.\(UUID().uuidString)")), live: false)
        service.ingestGATT([.init(name: "Yusuf iPad", level: 50), .init(name: "Yusuf iPhone", level: 70)], now: .now)
        XCTAssertEqual(service.visibleDevices.map(\.name), ["Yusuf iPhone"])
        XCTAssertEqual(service.hiddenDevices.map(\.name), ["Yusuf iPad"])
    }

    // MARK: Uyarılar

    func testDeviceAlertCrossesThresholdOnceWithHysteresis() {
        var engine = DeviceAlertEngine()
        func device(_ level: Int, charging: Bool = false) -> DeviceBattery {
            DeviceBattery(id: "k", name: "Keyboard", kind: .keyboard, level: level, isCharging: charging, lastSeen: .now, sources: [.hid])
        }
        let settings: [String: DeviceSettings] = [:]
        XCTAssertTrue(engine.evaluate([device(18)], settings: settings).isEmpty, "ilk görülme susturulur")
        XCTAssertTrue(engine.evaluate([device(17)], settings: settings).isEmpty, "zaten ateşlenmiş sayıldı")
        XCTAssertTrue(engine.evaluate([device(30)], settings: settings).isEmpty)   // yeniden silahlanır
        let low = engine.evaluate([device(19)], settings: settings)
        XCTAssertEqual(low.count, 1)
        XCTAssertEqual(low.first?.kind, .low(20))
        XCTAssertEqual(low.first?.title, "Keyboard pili azaldı")
        XCTAssertTrue(engine.evaluate([device(18)], settings: settings).isEmpty, "tekrar yok")
        let critical = engine.evaluate([device(9)], settings: settings)
        XCTAssertEqual(critical.first?.kind, .low(10))
        XCTAssertTrue(engine.evaluate([device(5, charging: true)], settings: settings).isEmpty, "şarjdayken uyarmaz")
        var off = DeviceSettings(); off.alertEnabled = false
        XCTAssertTrue(engine.evaluate([device(40)], settings: ["k": off]).isEmpty)
        XCTAssertTrue(engine.evaluate([device(2)], settings: ["k": off]).isEmpty)
    }

    func testDeviceAlertSkipsStaleDevices() {
        var engine = DeviceAlertEngine()
        let fresh = DeviceBattery(id: "m", name: "Mouse", kind: .mouse, level: 60, lastSeen: .now, sources: [.hid])
        _ = engine.evaluate([fresh], settings: [:])
        var stale = fresh; stale.level = 4; stale.isStale = true
        XCTAssertTrue(engine.evaluate([stale], settings: [:]).isEmpty)
    }

    func testDeviceSettingsThresholds() {
        var s = DeviceSettings()
        s.addThreshold(30); s.addThreshold(30); s.addThreshold(1)
        XCTAssertEqual(s.lowThresholds, [30, 20, 10])
        let decoded = try? JSONDecoder().decode(DeviceSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, DeviceSettings())
    }

    // MARK: iPhone / iPad (libimobiledevice sözlükleri)

    nonisolated(unsafe) static let lockdown: [String: Any] = ["DeviceName": "Yusuf iPhone", "ProductType": "iPhone14,2", "ProductVersion": "27.0", "SerialNumber": "F2LXXXXXXXXX"]
    nonisolated(unsafe) static let batteryDomain: [String: Any] = ["BatteryCurrentCapacity": 79, "BatteryIsCharging": false, "ExternalConnected": false, "FullyCharged": false]
    nonisolated(unsafe) static let ioreg: [String: Any] = [
        "Diagnostics": ["IORegistry": [
            "CycleCount": 208, "Temperature": 2980, "Voltage": 3970, "InstantAmperage": UInt64.max - 311, "Serial": "F5DXXXXXXXXXXXXXX",
            "AdapterDetails": ["Watts": 20, "Name": "20W USB-C Power Adapter", "IsWireless": false],
            "BatteryData": [
                "DesignCapacity": 3095, "NominalChargeCapacity": 2890, "AppleRawMaxCapacity": 2950, "AppleRawCurrentCapacity": 2330,
                "CellVoltage": [3968, 0], "Manufacturer": "Sunwoda",
                "LifetimeData": ["AverageTemperature": 274, "MinimumTemperature": 42, "MaximumTemperature": 459, "MaximumChargeCurrent": 2410,
                                 "MaximumDischargeCurrent": 3870, "MinimumPackVoltage": 3120, "MaximumPackVoltage": 4390, "TotalOperatingTime": 7240],
            ],
        ]],
        "Status": "Success",
    ]

    func testIOSMapperMapsLockdownAndDiagnostics() throws {
        let d = IOSDeviceMapper.details(udid: "UDID", connection: .wifi, lockdown: Self.lockdown, battery: Self.batteryDomain, ioreg: Self.ioreg, now: now)
        XCTAssertEqual(d.name, "Yusuf iPhone")
        XCTAssertEqual(d.modelName, "iPhone 13 Pro")
        XCTAssertEqual(d.systemVersion, "27.0")
        XCTAssertEqual(d.level, 79)
        XCTAssertFalse(d.isCharging)
        XCTAssertEqual(d.cycleCount, 208)
        XCTAssertEqual(d.designMAh, 3095)
        XCTAssertEqual(d.nominalMAh, 2890)
        XCTAssertEqual(d.healthPercent, 93)
        XCTAssertEqual(d.rawHealthPercent, 95)
        XCTAssertEqual(try XCTUnwrap(d.temperatureC), 29.8, accuracy: 0.001)
        XCTAssertEqual(d.voltageMV, 3970)
        XCTAssertEqual(d.amperageMA, -312, "64 bit işaretsiz → eksi akım (deşarj)")
        XCTAssertEqual(d.cellVoltagesMV, [3968])
        XCTAssertEqual(d.manufacturer, "Sunwoda")
        XCTAssertEqual(d.adapterWatts, 20)
        XCTAssertEqual(try XCTUnwrap(d.lifetimeAvgTempC), 27.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(d.lifetimeMinTempC), 4.2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(d.lifetimeMaxTempC), 45.9, accuracy: 0.001)
        XCTAssertEqual(d.lifetimeMaxChargeMA, 2410)
        XCTAssertEqual(d.lifetimeMaxDischargeMA, -3870)
        XCTAssertEqual(d.lifetimeMinVoltageMV, 3120)
        XCTAssertEqual(d.lifetimeOperatingHours, 7240)
        XCTAssertEqual(d.connection, .wifi)
    }

    func testIOSMapperToleratesMissingDiagnosticsAndBareDictionary() {
        let noIOReg = IOSDeviceMapper.details(udid: "U", connection: .usb, lockdown: Self.lockdown, battery: Self.batteryDomain, ioreg: nil)
        XCTAssertEqual(noIOReg.level, 79)
        XCTAssertNil(noIOReg.cycleCount)
        XCTAssertNil(noIOReg.healthPercent)
        let bare = IOSDeviceMapper.details(udid: "U", connection: .usb, lockdown: [:], battery: [:],
                                           ioreg: ["CycleCount": 12, "BatteryData": ["DesignCapacity": 1000, "NominalChargeCapacity": 800]])
        XCTAssertEqual(bare.name, "iOS cihazı")
        XCTAssertEqual(bare.cycleCount, 12)
        XCTAssertEqual(bare.healthPercent, 80)
        XCTAssertEqual(IOSDeviceMapper.modelName("iPhone99,9"), "iPhone")
        XCTAssertEqual(IOSDeviceMapper.modelName("iPad99,9"), "iPad")
    }

    func testIOSReportTextAndSerialScrubbing() {
        let d = IOSDeviceMapper.details(udid: "U", connection: .usb, lockdown: Self.lockdown, battery: Self.batteryDomain, ioreg: Self.ioreg, now: now)
        let full = IOSDeviceReport.text(d, now: now)
        XCTAssertTrue(full.contains("Yusuf iPhone pil raporu"))
        XCTAssertTrue(full.contains("Maksimum kapasite: %93"))
        XCTAssertTrue(full.contains("Döngü sayısı: 208"))
        XCTAssertTrue(full.contains("Seri no: F2LXXXXXXXXX"))
        XCTAssertTrue(full.contains("Pil seri no: F5DXXXXXXXXXXXXXX"))
        XCTAssertTrue(full.contains("Çalışma süresi: 7.240 sa (301 gün)"))
        let scrubbed = IOSDeviceReport.text(d, includeSerials: false, now: now)
        XCTAssertFalse(scrubbed.contains("F2LXXXXXXXXX"))
        XCTAssertFalse(scrubbed.contains("F5DXXXXXXXXXXXXXX"))
        XCTAssertTrue(IOSDeviceReport.fileName(d, now: now).hasSuffix(".txt"))
    }

    // MARK: Menü çubuğu sabitleme

    func testDeviceComponentCodableAndLegacyDecode() throws {
        let c = MenuBarComponent.device("yusuf iphone", name: "Yusuf iPhone")
        let back = try JSONDecoder().decode(MenuBarComponent.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.deviceID, "yusuf iphone")
        XCTAssertEqual(back.visual, .batteryCapsule)
        XCTAssertEqual(back.title, "Yusuf iPhone pili")
        let legacy = MenuBarComponent(.batteryLevel, visual: .batteryCapsule)
        let legacyBack = try JSONDecoder().decode(MenuBarComponent.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(legacyBack.deviceID)
    }

    @MainActor
    func testPinAndUnpinDeviceInMenuBarConfig() throws {
        let store = MenuBarConfigStore(defaults: try XCTUnwrap(UserDefaults(suiteName: "adalmon.test.\(UUID().uuidString)")))
        let before = store.config.components.count
        store.setPinned(device: "yusuf iphone", name: "Yusuf iPhone", true)
        store.setPinned(device: "yusuf iphone", name: "Yusuf iPhone", true)
        XCTAssertEqual(store.config.components.count, before + 1)
        XCTAssertTrue(store.isPinned(device: "yusuf iphone"))
        store.setPinned(device: "yusuf iphone", false)
        XCTAssertEqual(store.config.components.count, before)
    }

    @MainActor
    func testPinsSurviveSimpleCardEditing() throws {
        let store = MenuBarConfigStore(defaults: try XCTUnwrap(UserDefaults(suiteName: "adalmon.test.\(UUID().uuidString)")))
        store.setPinned(device: "yusuf iphone", name: "Yusuf iPhone", true)
        XCTAssertNotNil(store.cards, "sabitlenmiş cihaz basit düzenleyiciyi bozmamalı")
        store.apply(cards: MetricCardConfig.defaults)
        XCTAssertTrue(store.isPinned(device: "yusuf iphone"))
        store.apply(.kompakt)
        XCTAssertTrue(store.isPinned(device: "yusuf iphone"))
    }

    func testRenderKeyTracksPinnedDeviceOnly() {
        let pinned = MenuBarComponent.device("a")
        var v1 = WidgetValues.sample
        v1.devices = ["a": BatteryGlyphState(device: DeviceBattery(id: "a", name: "A", kind: .iPhone, level: 50, lastSeen: .now)),
                      "b": BatteryGlyphState(device: DeviceBattery(id: "b", name: "B", kind: .iPhone, level: 50, lastSeen: .now))]
        var v2 = v1
        v2.devices["b"]?.level = 10
        let config = MenuBarConfig.default
        XCTAssertEqual(MenuBarRenderKey(components: [pinned], config: config, values: v1), MenuBarRenderKey(components: [pinned], config: config, values: v2))
        v2.devices["a"]?.level = 49
        XCTAssertNotEqual(MenuBarRenderKey(components: [pinned], config: config, values: v1), MenuBarRenderKey(components: [pinned], config: config, values: v2))
        XCTAssertGreaterThan(ComponentRenderer.width(of: pinned, config: config, values: v1), 34, "simge + kapsül")
    }
}

/// Paketlenen kitaplıklar: yalnızca dlopen + sembol çözümleme (cihaz aranmaz, usbmuxd'ye bağlanılmaz).
final class BundledLibraryTests: XCTestCase {
    func testEmbeddedLibrariesLoadAndResolveSymbols() throws {
        let dir = try XCTUnwrap(Bundle.main.privateFrameworksPath)
        guard FileManager.default.fileExists(atPath: dir + "/" + LibIMobileDevice.imobiledeviceName) else {
            throw XCTSkip("kitaplıklar pakette yok")
        }
        XCTAssertNotNil(LibIMobileDevice.load(frameworksDirectory: dir), "libimobiledevice + libplist yüklenmeli ve tüm semboller çözülmeli")
    }

    func testLicenseNoticeListsAllBundledLibraries() {
        let names = Set(ThirdPartyNotice.all.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["libimobiledevice", "libplist", "libusbmuxd", "libimobiledevice-glue"]))
        XCTAssertTrue(ThirdPartyNotice.lgplStatement.contains("LGPL"))
    }
}
