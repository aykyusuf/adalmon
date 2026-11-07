import XCTest
@testable import Adalmon

final class WidgetSnapshotTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testEncodeDecodeRoundTrip() throws {
        let snap = WidgetSnapshot.sample(now: t0)
        let data = try snap.encoded()
        let back = try WidgetSnapshot.decode(data)
        XCTAssertEqual(back, snap)
        XCTAssertEqual(back.schemaVersion, 1)
        XCTAssertEqual(back.system?.mobileTodayBytes, 1_260_000_000)
    }

    func testFileRoundTripAndMissingFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(WidgetSnapshotStore.read(from: url))
        XCTAssertTrue(WidgetSnapshotStore.write(.sample(now: t0), to: url))
        XCTAssertEqual(WidgetSnapshotStore.read(from: url), .sample(now: t0))
        // Bozuk dosya çökmez, nil döner.
        try Data("{bozuk".utf8).write(to: url)
        XCTAssertNil(WidgetSnapshotStore.read(from: url))
    }

    func testDecodingToleratesMissingAndUnknownFields() throws {
        let json = #"{"generatedAt": 1800000000, "futureField": 7, "devices": [{"id":"a","name":"A","symbol":"x","lastSeen":1800000000,"level":50}]}"#
        let snap = try WidgetSnapshot.decode(Data(json.utf8))
        XCTAssertEqual(snap.schemaVersion, 1)
        XCTAssertNil(snap.mac)
        XCTAssertNil(snap.system)
        XCTAssertEqual(snap.devices.first?.level, 50)
        XCTAssertEqual(snap.devices.first?.isConnected, true)
    }

    func testStaleAfterFifteenMinutes() {
        let snap = WidgetSnapshot.sample(now: t0)
        XCTAssertFalse(snap.isStale(at: t0.addingTimeInterval(14 * 60)))
        XCTAssertTrue(snap.isStale(at: t0.addingTimeInterval(15 * 60 + 1)))
    }

    func testHasSameContentIgnoresTimestamps() {
        var a = WidgetSnapshot.sample(now: t0)
        var b = a
        b.generatedAt = t0.addingTimeInterval(500)
        b.devices[0].lastSeen = t0.addingTimeInterval(500)
        XCTAssertTrue(a.hasSameContent(as: b))
        a.mac?.level = 77
        XCTAssertFalse(a.hasSameContent(as: b))
    }

    func testTimelinePlanAddsStaleEntry() {
        let plan = WidgetTimelinePlan.make(snapshotDate: t0, now: t0.addingTimeInterval(60))
        XCTAssertEqual(plan.dates.count, 2)
        XCTAssertEqual(plan.dates[1], t0.addingTimeInterval(15 * 60 + 1))
        // Zaten eskiyse tek giriş.
        XCTAssertEqual(WidgetTimelinePlan.make(snapshotDate: t0, now: t0.addingTimeInterval(3600)).dates.count, 1)
        XCTAssertEqual(WidgetTimelinePlan.make(snapshotDate: nil, now: t0).dates, [t0])
    }

    func testRouteURLs() {
        for route in AdalmonRoute.allCases { XCTAssertEqual(AdalmonRoute(url: route.url), route) }
        XCTAssertEqual(AdalmonRoute(url: URL(string: "adalmon://battery")!), .battery)
        XCTAssertNil(AdalmonRoute(url: URL(string: "https://battery")!))
        XCTAssertNil(AdalmonRoute(url: URL(string: "adalmon://bilinmeyen")!))
    }

    // MARK: Cihaz seçimi

    func testAutomaticSelectionPutsMacFirstThenConnectedDevices() {
        let items = WidgetBatteryOptions().items(from: .sample(now: t0))
        XCTAssertEqual(items.first?.name, "Bu Mac")
        XCTAssertEqual(items.map(\.id), ["__mac__", "yusuf iphone", "airpods", "keyboard", "ipad", "mouse", "watch"])
        XCTAssertEqual(items.last?.isConnected, false) // bağlı olmayan en sonda
    }

    func testIncludeMacOff() {
        var o = WidgetBatteryOptions()
        o.includeMac = false
        XCTAssertFalse(o.items(from: .sample(now: t0)).contains { $0.isMac })
    }

    func testCustomSelectionKeepsUserOrderAndSkipsMissing() {
        var o = WidgetBatteryOptions()
        o.selection = .custom
        o.customIDs = ["ipad", "yok", "keyboard"]
        o.includeMac = false
        XCTAssertEqual(o.items(from: .sample(now: t0)).map(\.id), ["ipad", "keyboard"])
    }

    func testSameAsMenuBarUsesPinnedOrder() {
        var o = WidgetBatteryOptions()
        o.selection = .sameAsMenuBar
        var snap = WidgetSnapshot.sample(now: t0)
        snap.pinnedDeviceIDs = ["airpods", "yusuf iphone"]
        XCTAssertEqual(o.items(from: snap).map(\.id), ["__mac__", "airpods", "yusuf iphone"])
        snap.pinnedDeviceIDs = []
        o.includeMac = false
        XCTAssertTrue(o.items(from: snap).isEmpty)
        XCTAssertEqual(o.emptyHint(snapshot: snap), "Menü çubuğuna sabitlenmiş cihaz yok")
    }

    func testCapacityGrowsWithSize() {
        for style in WidgetBatteryStyle.allCases {
            var o = WidgetBatteryOptions()
            o.style = style
            XCTAssertLessThanOrEqual(o.capacity(for: .small), o.capacity(for: .medium))
            XCTAssertLessThanOrEqual(o.capacity(for: .medium), max(o.capacity(for: .large), o.capacity(for: .medium)))
        }
        XCTAssertEqual(WidgetBatteryOptions().capacity(for: .small), 4)
    }

    // MARK: Oluşturucu

    func testBuilderMapsAppStateAndHidesDevices() {
        var reading = BatteryReading.sampleCharging
        reading.timestamp = t0
        var hiddenDevice = DeviceBattery.samples[2]
        hiddenDevice.id = "gizli"
        let snap = WidgetSnapshotBuilder.make(
            now: t0, battery: reading, devices: DeviceBattery.samples + [hiddenDevice], hiddenDeviceIDs: ["gizli"], pinnedDeviceIDs: ["yusuf iphone"],
            system: nil, mobileToday: 5, dailyCap: 10, cycleUsed: nil, monthlyCap: nil, isOnMobile: false)
        XCTAssertEqual(snap.mac?.level, 64)
        XCTAssertEqual(snap.mac?.state, .charging)
        XCTAssertEqual(snap.mac?.minutesToFull, 40)
        XCTAssertEqual(snap.mac?.adapterWatts, 70)
        XCTAssertEqual(snap.mac?.healthPercent, 86)
        XCTAssertFalse(snap.devices.contains { $0.id == "gizli" })
        XCTAssertEqual(snap.devices.first?.symbol, "iphone")
        XCTAssertEqual(snap.pinnedDeviceIDs, ["yusuf iphone"])
        XCTAssertNil(snap.system)
        XCTAssertNil(WidgetSnapshotBuilder.make(now: t0, battery: nil, devices: [], hiddenDeviceIDs: [], pinnedDeviceIDs: [], system: nil,
                                                mobileToday: 0, dailyCap: 1, cycleUsed: nil, monthlyCap: nil, isOnMobile: false).mac)
    }
}

final class WidgetPublishGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func snap(_ level: Int, at date: Date) -> WidgetSnapshot {
        var s = WidgetSnapshot.sample(now: date)
        s.mac?.level = level
        return s
    }

    func testFirstTickWritesAndReloads() {
        var gate = WidgetPublishGate()
        let plan = gate.evaluate(now: t0, forced: false) { snap(50, at: t0) }
        XCTAssertNotNil(plan?.snapshot)
        XCTAssertEqual(plan?.reload, true)
    }

    func testTicksInsideWriteIntervalDoNotBuild() {
        var gate = WidgetPublishGate()
        _ = gate.evaluate(now: t0, forced: false) { snap(50, at: t0) }
        var builds = 0
        for s in stride(from: 1.0, to: 59.0, by: 1.0) {
            let plan = gate.evaluate(now: t0.addingTimeInterval(s), forced: false) { builds += 1; return snap(49, at: t0) }
            XCTAssertNil(plan)
        }
        XCTAssertEqual(builds, 0)
    }

    func testChangedContentWritesAfter60sButReloadWaitsFor5Min() {
        var gate = WidgetPublishGate()
        _ = gate.evaluate(now: t0, forced: false) { snap(50, at: t0) }
        let t1 = t0.addingTimeInterval(61)
        let plan1 = gate.evaluate(now: t1, forced: false) { snap(49, at: t1) }
        XCTAssertNotNil(plan1?.snapshot)
        XCTAssertEqual(plan1?.reload, false)
        // 5 dk dolunca (içerik aynı) yalnızca yenileme.
        var builds = 0
        let t2 = t0.addingTimeInterval(301)
        let plan2 = gate.evaluate(now: t2, forced: false) { builds += 1; return snap(49, at: t2) }
        XCTAssertNil(plan2?.snapshot)
        XCTAssertEqual(plan2?.reload, true)
        XCTAssertLessThanOrEqual(builds, 1)
    }

    func testUnchangedContentSkipsUntilHeartbeat() {
        var gate = WidgetPublishGate()
        _ = gate.evaluate(now: t0, forced: false) { snap(50, at: t0) }
        let t1 = t0.addingTimeInterval(120)
        XCTAssertNil(gate.evaluate(now: t1, forced: false) { snap(50, at: t1) })
        let t2 = t0.addingTimeInterval(601)
        let plan = gate.evaluate(now: t2, forced: false) { snap(50, at: t2) }
        XCTAssertNotNil(plan?.snapshot) // nabız
        XCTAssertEqual(plan?.snapshot?.generatedAt, t2)
        XCTAssertEqual(plan?.reload, true)
    }

    func testForcedWritesImmediatelyWithShortReloadGap() {
        var gate = WidgetPublishGate()
        _ = gate.evaluate(now: t0, forced: false) { snap(50, at: t0) }
        let t1 = t0.addingTimeInterval(5)
        // Tak/çıkar hemen yazılır ama yenileme 30 sn'den önce yapılmaz.
        let early = gate.evaluate(now: t1, forced: true) { snap(51, at: t1) }
        XCTAssertNotNil(early?.snapshot)
        XCTAssertEqual(early?.reload, false)
        let t2 = t0.addingTimeInterval(40)
        let late = gate.evaluate(now: t2, forced: true) { snap(52, at: t2) }
        XCTAssertEqual(late?.reload, true)
    }

    @MainActor
    func testPublisherCountsWritesAndReloads() {
        final class Sink: @unchecked Sendable {
            let lock = NSLock()
            var written: [WidgetSnapshot] = []
            func add(_ s: WidgetSnapshot) { lock.lock(); written.append(s); lock.unlock() }
        }
        let sink = Sink()
        var reloaded: [[String]] = []
        let publisher = WidgetPublisher(write: { sink.add($0) }, reload: { reloaded.append($0) })
        publisher.tick(now: t0) { self.snap(50, at: self.t0) }
        publisher.tick(now: t0.addingTimeInterval(10)) { self.snap(40, at: self.t0) }
        XCTAssertEqual(publisher.writeCount, 1)
        XCTAssertEqual(publisher.reloadCount, 1)
        XCTAssertEqual(reloaded.first, WidgetShared.Kind.all)
        XCTAssertEqual(sink.written.count, 1)
    }
}
