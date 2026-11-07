import Foundation
import XCTest
@testable import Adalmon

final class BatteryLogicTests: XCTestCase {
    // MARK: Çözümleme

    private func fixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/AppleSmartBattery-mac16-1.plist")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testParsesRealMacFixture() throws {
        let r = AppleSmartBatteryParser.parse(registry: try fixture(), lowPowerMode: false)
        XCTAssertEqual(r.level, 100)
        XCTAssertEqual(r.cycles, 178)
        XCTAssertEqual(r.designCycles, 1000, "DesignCycleCount9C (IOPS'taki 300 değil)")
        XCTAssertEqual(r.rawMaxMAh, 5132, "macOS 27: kapasiteler BatteryData içinde")
        XCTAssertEqual(r.rawCurrentMAh, 5108)
        XCTAssertEqual(r.designMAh, 6249)
        XCTAssertEqual(r.nominalMAh, 5284)
        XCTAssertEqual(r.rawHealthPercent, 82)
        XCTAssertEqual(r.nominalHealthPercent, 85)
        XCTAssertTrue(r.isPluggedIn)
        XCTAssertFalse(r.isCharging)
        XCTAssertEqual(r.state, .full)
        XCTAssertNil(r.timeToFullMinutes, "65535 sentinel = bilinmiyor")
        XCTAssertNil(r.timeToEmptyMinutes)
        XCTAssertEqual(r.adapterWatts, 68)
        XCTAssertEqual(r.adapterLabelWatts, 70, "Etiketteki 70W, AdapterDetails.Watts 68")
        XCTAssertEqual(r.adapterDisplayName, "70W USB-C Power Adapter")
        XCTAssertEqual(r.systemPowerMW, 3864)
        XCTAssertEqual(r.batteryPowerMW, 0)
        XCTAssertEqual(r.cable, .usbC)
        XCTAssertEqual(r.voltageMV, 12_870)
    }

    func testLegacyTopLevelCapacityKeysAndSignedAmperage() {
        let registry: [String: Any] = [
            "AppleRawMaxCapacity": 4000, "DesignCapacity": 5000, "AppleRawCurrentCapacity": 2000, "NominalChargeCapacity": 4100,
            "CurrentCapacity": 50, "MaxCapacity": 100, "ExternalConnected": false, "IsCharging": false,
            "InstantAmperage": NSNumber(value: UInt64.max - 1_299), // -1300 (64 bit işaretsiz)
            "AvgTimeToEmpty": 187, "AvgTimeToFull": 65_535, "CycleCount": 40,
        ]
        let r = AppleSmartBatteryParser.parse(registry: registry)
        XCTAssertEqual(r.rawMaxMAh, 4000)
        XCTAssertEqual(r.rawHealthPercent, 80)
        XCTAssertEqual(r.amperageMA, -1300)
        XCTAssertEqual(r.timeToEmptyMinutes, 187)
        XCTAssertNil(r.timeToFullMinutes)
        XCTAssertEqual(r.designCycles ?? 1000, 1000)
        XCTAssertEqual(r.state, .onBattery)
    }

    func testPowerSourceOverridesAndChargingTimes() {
        let ps: [String: Any] = ["Current Capacity": 64, "Max Capacity": 100, "Time to Full Charge": 40, "Time to Empty": -1, "Is Charging": true]
        let reg: [String: Any] = ["ExternalConnected": true, "IsCharging": true, "AvgTimeToFull": 65_535]
        let r = AppleSmartBatteryParser.parse(registry: reg, powerSource: ps)
        XCTAssertEqual(r.level, 64)
        XCTAssertEqual(r.state, .charging)
        XCTAssertEqual(r.timeToFullMinutes, 40)
        XCTAssertNil(r.timeToEmptyMinutes)
        XCTAssertEqual(BatteryFormat.statusLine(r), "Şarj oluyor · %100'e 0:40")
    }

    // MARK: Biçim ve sağlık

    func testTimeFormatting() {
        XCTAssertEqual(BatteryFormat.clock(135), "2:15")
        XCTAssertEqual(BatteryFormat.clock(40), "0:40")
        XCTAssertEqual(BatteryFormat.long(192), "3 sa 12 dk")
        XCTAssertEqual(BatteryFormat.long(40), "40 dk")
        XCTAssertEqual(BatteryFormat.long(120), "2 sa")
        XCTAssertEqual(BatteryFormat.lowMessage(level: 15, minutes: 9), "%15 kaldı · 9 dk")
        XCTAssertEqual(BatteryFormat.statusLine(.sample), "Pil · 3 sa 12 dk kaldı")
        var full = BatteryReading.sample
        full.isPluggedIn = true; full.isFullyCharged = true; full.level = 100
        XCTAssertEqual(BatteryFormat.statusLine(full), "Tam şarjlı")
        XCTAssertNil(BatteryFormat.menuBarTime(full))
        XCTAssertEqual(BatteryFormat.menuBarTime(.sample), "3:12")
        XCTAssertEqual(BatteryFormat.menuBarTime(.sampleCharging), "0:40")
    }

    func testHealthComputations() {
        var r = BatteryReading.sample
        XCTAssertEqual(r.rawHealthPercent, 82)
        XCTAssertEqual(r.nominalHealthPercent, 85)
        XCTAssertEqual(r.primaryHealthPercent, 86, "Apple değeri öncelikli")
        r.appleMaxCapacityPercent = nil
        XCTAssertEqual(r.primaryHealthPercent, 85)
        r.designMAh = 0
        XCTAssertNil(r.rawHealthPercent)
        XCTAssertEqual(BatteryReading.ratio(5132, 6249), 82)
    }

    func testSystemProfilerParsing() {
        let json = #"{"SPPowerDataType":[{"_name":"spbattery_information","sppower_battery_health_info":{"sppower_battery_cycle_count":178,"sppower_battery_health":"Good","sppower_battery_health_maximum_capacity":"%86"}}]}"#
        XCTAssertEqual(BatteryHealthProvider.parse(json: Data(json.utf8)), 86)
        XCTAssertNil(BatteryHealthProvider.parse(json: Data("{}".utf8)))
        let old = Date(timeIntervalSinceNow: -7 * 3_600)
        XCTAssertTrue(BatteryHealthProvider.needsRefresh(.init(percent: 86, date: old)))
        XCTAssertFalse(BatteryHealthProvider.needsRefresh(.init(percent: 86, date: Date(timeIntervalSinceNow: -3_600))))
        XCTAssertTrue(BatteryHealthProvider.needsRefresh(.init(percent: nil, date: nil)))
    }

    func testRealReadOnThisMac() {
        guard let r = BatteryReader.read() else { return } // masaüstü Mac'te pil yok
        print("BATTERY_REAL_TEMP: \(TemperatureSampler().sample()?.battery.map { String($0) } ?? "nil")")
        XCTAssertTrue((0...100).contains(r.level))
        XCTAssertNotNil(r.cycles)
        print("BATTERY_REAL: level=\(r.level) charging=\(r.isCharging) plugged=\(r.isPluggedIn) cycles=\(r.cycles ?? -1)/\(r.designCycles ?? -1) rawMax=\(r.rawMaxMAh ?? -1) design=\(r.designMAh ?? -1) nominal=\(r.nominalMAh ?? -1) rawHealth=\(r.rawHealthPercent ?? -1) nominalHealth=\(r.nominalHealthPercent ?? -1) adapter=\(r.adapterName ?? "-")/\(r.adapterWatts ?? -1)W cable=\(r.cable) systemW=\(r.systemPowerW ?? -1) mV=\(r.voltageMV ?? -1) mA=\(r.amperageMA ?? -1) tEmpty=\(r.timeToEmptyMinutes ?? -1) tFull=\(r.timeToFullMinutes ?? -1)")
    }

    // MARK: Uyarılar

    private func reading(_ level: Int, plugged: Bool = false, charging: Bool = false, full: Bool = false) -> BatteryReading {
        var r = BatteryReading.sample
        r.level = level; r.isPluggedIn = plugged; r.isCharging = charging; r.isFullyCharged = full
        r.timeToEmptyMinutes = plugged ? nil : level * 2
        r.timeToFullMinutes = charging ? 30 : nil
        return r
    }

    func testLowThresholdFiresOnceWithHysteresis() {
        var engine = BatteryAlertEngine()
        let config = BatteryAlertConfig()
        XCTAssertTrue(engine.evaluate(reading(40), config: config).isEmpty, "ilk okuma sessiz")
        XCTAssertTrue(engine.evaluate(reading(21), config: config).isEmpty)
        let e20 = engine.evaluate(reading(20), config: config)
        XCTAssertEqual(e20.map(\.kind), [.low(20)])
        XCTAssertEqual(e20.first?.message, "%20 kaldı · 40 dk")
        XCTAssertTrue(engine.evaluate(reading(19), config: config).isEmpty, "aynı eşik tekrar etmez")
        XCTAssertTrue(engine.evaluate(reading(20), config: config).isEmpty, "titreme tekrar uyarmaz")
        XCTAssertTrue(engine.evaluate(reading(22), config: config).isEmpty)
        XCTAssertTrue(engine.evaluate(reading(20), config: config).isEmpty, "histerezis (eşik+3) içinde yeniden silahlanmaz")
        XCTAssertEqual(engine.evaluate(reading(10), config: config).map(\.kind), [.low(10)])
        XCTAssertEqual(engine.evaluate(reading(5), config: config).map(\.kind), [.low(5)])
        // 24'e çıkınca (20+3 aşıldı) yeniden silahlanır
        _ = engine.evaluate(reading(24), config: config)
        XCTAssertEqual(engine.evaluate(reading(19), config: config).map(\.kind), [.low(20)])
    }

    func testSleepJumpReportsOnlyMostSevereThreshold() {
        var engine = BatteryAlertEngine()
        let config = BatteryAlertConfig()
        _ = engine.evaluate(reading(60), config: config)
        let events = engine.evaluate(reading(4), config: config)
        XCTAssertEqual(events.map(\.kind), [.low(5)], "20/10/5 birden geçildi: yalnız en şiddetlisi")
        XCTAssertTrue(engine.evaluate(reading(3), config: config).isEmpty)
    }

    func testStartupBelowThresholdIsSilent() {
        var engine = BatteryAlertEngine()
        XCTAssertTrue(engine.evaluate(reading(8), config: BatteryAlertConfig()).isEmpty)
        XCTAssertTrue(engine.evaluate(reading(7), config: BatteryAlertConfig()).isEmpty)
    }

    func testChargedThresholdsAndPlugEvents() {
        var config = BatteryAlertConfig()
        config.pluggedIn.enabled = true
        config.unplugged.enabled = true
        config.charged[0].action.enabled = true
        var engine = BatteryAlertEngine()
        _ = engine.evaluate(reading(70), config: config)
        let plug = engine.evaluate(reading(70, plugged: true, charging: true), config: config)
        XCTAssertEqual(plug.map(\.kind), [.pluggedIn])
        XCTAssertEqual(plug.first?.message, "%70 · %100'e 0:30")
        XCTAssertEqual(engine.evaluate(reading(80, plugged: true, charging: true), config: config).map(\.kind), [.charged(80)])
        XCTAssertTrue(engine.evaluate(reading(81, plugged: true, charging: true), config: config).isEmpty)
        XCTAssertEqual(engine.evaluate(reading(100, plugged: true, charging: false, full: true), config: config).map(\.kind), [.charged(100)])
        XCTAssertTrue(engine.evaluate(reading(100, plugged: true, full: true), config: config).isEmpty, "tam şarjda tekrar etmez")
        XCTAssertEqual(engine.evaluate(reading(100), config: config).map(\.kind), [.unplugged])
    }

    func testDisabledAlertsAndConfigCodable() throws {
        var config = BatteryAlertConfig()
        config.enabled = false
        var engine = BatteryAlertEngine()
        _ = engine.evaluate(reading(50), config: config)
        XCTAssertTrue(engine.evaluate(reading(5), config: config).isEmpty)
        config.enabled = true
        XCTAssertTrue(engine.evaluate(reading(4), config: config).isEmpty, "kapalıyken geçilen eşik açılınca sahte uyarı vermez")

        var c = BatteryAlertConfig()
        c.addLow(15); c.addLow(15); c.addLow(0)
        XCTAssertEqual(c.low.map(\.value), [20, 15, 10, 5])
        c.addCharged(90)
        XCTAssertEqual(c.charged.map(\.value), [80, 90, 100])
        let decoded = try JSONDecoder().decode(BatteryAlertConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded, c)
    }

    // MARK: Günlük toplamlar

    func testEnergyTrackerSumsDropsOnly() {
        let totals = BatteryEnergyTracker.totals(levels: [("d1", 100), ("d1", 97), ("d1", 98), ("d1", 90), ("d2", 91), ("d2", 80)])
        XCTAssertEqual(totals["d1"], 11, "3 + 8; artış sayılmaz")
        XCTAssertEqual(totals["d2"], 11)
        var t = BatteryEnergyTracker()
        XCTAssertNil(t.consume(level: 50, day: "d"))
        XCTAssertEqual(t.consume(level: 60, day: "d")?.chargedPercent, 10)
    }

    func testScreenOnClockSplitsAtMidnightAndTracksSleep() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let t0 = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 23, minute: 50)))
        var clock = ScreenOnClock(now: t0, calendar: cal)
        let closed = clock.update(screensAwake: false, at: t0.addingTimeInterval(20 * 60))
        XCTAssertEqual(closed, [.init(day: "2026-11-05", seconds: 600), .init(day: "2026-11-06", seconds: 600)])
        XCTAssertFalse(clock.isOn)
        XCTAssertTrue(clock.flush(at: t0.addingTimeInterval(3_600)).isEmpty, "ekran kapalıyken sayılmaz")
        clock.update(screensAwake: true, at: t0.addingTimeInterval(3_600))
        clock.update(sessionActive: false, at: t0.addingTimeInterval(3_600 + 300))
        XCTAssertEqual(clock.flush(at: t0.addingTimeInterval(7_200)), [])
        let tail = clock.update(sessionActive: true, at: t0.addingTimeInterval(7_200))
        XCTAssertTrue(tail.isEmpty)
        XCTAssertEqual(clock.flush(at: t0.addingTimeInterval(7_260)).first?.seconds, 60)
    }

    // MARK: Depo

    func testStoreRollupsRetentionAndLastFullCharge() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bat-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UsageStore(path: dir.appending(path: "u.sqlite").path)
        let cal = UsageStore.keyCalendar
        let now = Date.now
        let day = UsageStore.dayKey(now, calendar: cal)
        let t = Int(now.timeIntervalSince1970)
        await store.recordBattery(
            samples: [BatterySample(ts: t - 120, pct: 100, plugged: true, tempC: 30.0, rawMaxMAh: 5132, nominalMAh: 5284, cycles: 178),
                      BatterySample(ts: t - 60, pct: 98, tempC: 32.0, rawMaxMAh: 5132, nominalMAh: 5284, cycles: 178)],
            deltas: [.init(day: day, consumedPercent: 2, chargedPercent: 0)],
            screen: [.init(day: day, seconds: 3_600)])
        await store.recordBattery(samples: [], deltas: [.init(day: day, consumedPercent: 3, chargedPercent: 0)], screen: [.init(day: day, seconds: 600)])
        let rows = await store.batteryDaily(fromDay: day, toDay: day)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.consumedPercent, 5, accuracy: 0.001)
        XCTAssertEqual(row.screenSeconds, 4_200)
        XCTAssertEqual(row.maxCapacityMAh, 5132)
        XCTAssertEqual(row.cycles, 178)
        XCTAssertEqual(row.minPercent, 98)
        XCTAssertEqual(row.maxPercent, 100)
        XCTAssertEqual(try XCTUnwrap(row.avgTemp), 31, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(row.maxTemp), 32, accuracy: 0.05)
        let samples = await store.batterySamples(from: now.addingTimeInterval(-600))
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.last?.pct, 98)
        let full = await store.lastFullCharge()
        XCTAssertEqual(full.map { Int($0.timeIntervalSince1970) }, t - 120)

        // Saklama: 15 günlük dakikalık ve 401 günlük günlük satır silinir.
        let old = t - 15 * 86_400
        await store.recordBattery(samples: [BatterySample(ts: old, pct: 50)])
        let ancient = cal.date(byAdding: .day, value: -401, to: now) ?? now
        await store.recordBattery(samples: [BatterySample(ts: Int(ancient.timeIntervalSince1970), pct: 50)])
        await store.batteryMaintenance()
        let afterRows = await store.batteryRowCount()
        XCTAssertEqual(afterRows, 2)
        let oldDaily = await store.batteryDaily(fromDay: "2000-01-01", toDay: UsageStore.dayKey(ancient, calendar: cal))
        XCTAssertTrue(oldDaily.isEmpty)
    }

    func testMinuteSeriesBucketing() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bat-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UsageStore(path: dir.appending(path: "u.sqlite").path)
        let base = Int(Date.now.timeIntervalSince1970) / 3_600 * 3_600 - 7_200
        await store.recordBattery(samples: (0..<120).map { BatterySample(ts: base + $0 * 60, pct: 100 - $0 / 2, charging: $0 > 100) })
        let raw = await store.batterySamples(from: Date(timeIntervalSince1970: TimeInterval(base)), bucketSeconds: 60)
        XCTAssertEqual(raw.count, 120)
        let hourly = await store.batterySamples(from: Date(timeIntervalSince1970: TimeInterval(base)), bucketSeconds: 3_600)
        XCTAssertEqual(hourly.count, 2)
        XCTAssertTrue(hourly[1].charging, "kovada şarj varsa işaretli")
    }

    // MARK: Menü çubuğu bileşeni

    func testBatteryComponentCodableAndRenderKey() throws {
        let c = MenuBarComponent(.batteryLevel, visual: .batteryCapsule, battery: BatteryGlyphOptions(showTime: true, statusColors: false, size: .large))
        XCTAssertTrue(c.isValid)
        let decoded = try JSONDecoder().decode(MenuBarComponent.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded.battery, c.battery)
        // Eski JSON (battery alanı yok) çözülür.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any])
        json["battery"] = nil
        let legacy = try JSONDecoder().decode(MenuBarComponent.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.battery, BatteryGlyphOptions())
        // Geçersiz birleşim normalize olur.
        var bad = MenuBarComponent(.cpu)
        bad.visual = .batteryCapsule
        XCTAssertNotEqual(bad.normalized().visual, .batteryCapsule)

        var values = WidgetValues.sample
        values.battery = BatteryGlyphState(.sample)
        let config = MenuBarConfig(components: [c])
        let key1 = MenuBarRenderKey(components: [c], config: config, values: values)
        var again = values
        again.cpu = 0.9 // alakasız değişim
        XCTAssertEqual(key1, MenuBarRenderKey(components: [c], config: config, values: again), "değişmeyen pil için yeniden çizim yok")
        var changed = values
        changed.battery = BatteryGlyphState(.sampleCharging)
        XCTAssertNotEqual(key1, MenuBarRenderKey(components: [c], config: config, values: changed))
        XCTAssertGreaterThan(ComponentRenderer.width(of: c, config: config, values: changed), ComponentRenderer.width(of: c, config: config, values: .init()))
    }

    // MARK: İzleyici (uçtan uca)

    @MainActor
    func testMonitorFiresAlertAndPersistsSamples() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bat-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UsageStore(path: dir.appending(path: "u.sqlite").path)
        var current = reading(40)
        var config = BatteryAlertConfig()
        for i in config.low.indices { config.low[i].action = .init(presentation: .none, sound: nil, notification: true) }
        var notified: [String] = []
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "bat-test-\(UUID().uuidString)"))
        defaults.set(86, forKey: "battery.appleMaxCapacity")
        defaults.set(Date(), forKey: "battery.appleMaxCapacityDate")
        let monitor = BatteryMonitor(store: store, alertConfig: { config }, notify: { t, b in notified.append("\(t)|\(b)") },
                                     defaults: defaults, readProvider: { current })
        monitor.start()
        defer { monitor.stop() }
        XCTAssertEqual(monitor.reading?.level, 40)
        XCTAssertEqual(monitor.reading?.appleMaxCapacityPercent, 86, "önbellekteki Apple sağlığı okumaya işlenir")
        current = reading(19)
        monitor.setVisible(true)
        XCTAssertEqual(monitor.reading?.level, 19)
        XCTAssertEqual(notified.count, 1)
        XCTAssertTrue(notified[0].contains("%19 kaldı"))
        current = reading(18)
        monitor.setVisible(false)
        monitor.setVisible(true)
        XCTAssertEqual(notified.count, 1, "aynı eşik tekrar etmez")
        monitor.flushNow()
        try await Task.sleep(for: .milliseconds(300))
        let rows = await store.batteryRowCount()
        XCTAssertGreaterThanOrEqual(rows, 1)
        let day = await store.batteryDaily(fromDay: UsageStore.dayKey(), toDay: UsageStore.dayKey())
        XCTAssertGreaterThanOrEqual(day.first?.consumedPercent ?? 0, 21, "40 → 19 düşüşü günlük enerjiye yazıldı")
    }
}
