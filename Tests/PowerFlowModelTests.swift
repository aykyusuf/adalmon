import XCTest
@testable import Adalmon

final class PowerFlowModelTests: XCTestCase {
    // MARK: Fixtures

    /// Fişte, şarj oluyor: adaptör 52,3 W veriyor; pil 38,4 W alıyor; Mac 13,9 W.
    private var charging: BatteryReading {
        var r = BatteryReading.sampleCharging
        r.systemPowerMW = 52_300; r.batteryPowerMW = 38_400; r.systemLoadMW = 13_900
        r.adapterVoltageMV = 20_000; r.adapterCurrentMA = 3_390; r.adapterEfficiencyLossMW = 2_100
        r.systemVoltageInMV = 20_204; r.systemCurrentInMA = 2_589
        return r
    }

    /// Fişte, pil %100: adaptör yalnız Mac'e (gerçek makine okuması).
    private var full: BatteryReading {
        var r = BatteryReading.sampleCharging
        r.level = 100; r.isCharging = false; r.isFullyCharged = true; r.amperageMA = 0
        r.systemPowerMW = 36_439; r.batteryPowerMW = 0; r.systemLoadMW = 36_439
        return r
    }

    private var onBattery: BatteryReading {
        var r = BatteryReading.sample
        r.systemPowerMW = 0; r.batteryPowerMW = -15_800; r.systemLoadMW = 15_800
        return r
    }

    private var phone: PowerPortAccessory {
        PowerPortAccessory(id: "usb.1", name: "iPhone", kind: .phone, portName: "USB‑C 2", detail: "Apple · USB", allocatedMW: 2_500)
    }

    // MARK: Modlar

    func testPluggedChargingSplitsAdapterIntoMacAndBattery() throws {
        let m = PowerFlowModel.make(charging)
        XCTAssertEqual(m.mode, .pluggedCharging)
        let toMac = try XCTUnwrap(m.edge(.adapterToMac)), toBat = try XCTUnwrap(m.edge(.adapterToBattery))
        XCTAssertEqual(toMac.from, .adapter); XCTAssertEqual(toMac.to, .mac)
        XCTAssertEqual(toBat.from, .adapter); XCTAssertEqual(toBat.to, .battery)
        XCTAssertEqual(toMac.watts ?? 0, 13.9, accuracy: 0.01)
        XCTAssertEqual(toBat.watts ?? 0, 38.4, accuracy: 0.01)
        XCTAssertNil(m.edge(.batteryToMac))
        XCTAssertTrue(toMac.isActive && toBat.isActive)
        XCTAssertEqual(toMac.tint, .green); XCTAssertEqual(toBat.tint, .blue)
        // Bölünme toplamı adaptör çıkışına yakın.
        XCTAssertEqual((toMac.watts ?? 0) + (toBat.watts ?? 0), 52.3, accuracy: 0.1)
        XCTAssertTrue(m.hasMotion)
    }

    func testPluggedFullFlowsAdapterToMacOnly() throws {
        let m = PowerFlowModel.make(full)
        XCTAssertEqual(m.mode, .pluggedIdle)
        XCTAssertEqual(m.edges.count, 1)
        let e = try XCTUnwrap(m.edge(.adapterToMac))
        XCTAssertEqual(e.watts ?? 0, 36.439, accuracy: 0.01)
        XCTAssertNil(m.edge(.adapterToBattery)); XCTAssertNil(m.edge(.batteryToMac))
        XCTAssertFalse(try XCTUnwrap(m.node(.battery)).isActive, "dolu pil boşta")
    }

    func testPluggedNotChargingBehavesLikeFull() {
        var r = full
        r.isFullyCharged = false; r.level = 80 // şarj sınırı: fişte, şarj olmuyor
        let m = PowerFlowModel.make(r)
        XCTAssertEqual(m.mode, .pluggedIdle)
        XCTAssertEqual(m.edges.map(\.kind), [.adapterToMac])
        XCTAssertEqual(m.node(.battery)?.caption, "şarj olmuyor")
    }

    func testOnBatteryFlowsBatteryToMac() throws {
        let m = PowerFlowModel.make(onBattery)
        XCTAssertEqual(m.mode, .onBattery)
        XCTAssertEqual(m.edges.map(\.kind), [.batteryToMac])
        let e = try XCTUnwrap(m.edge(.batteryToMac))
        XCTAssertEqual(e.from, .battery); XCTAssertEqual(e.to, .mac)
        XCTAssertEqual(e.watts ?? 0, 15.8, accuracy: 0.01)
        XCTAssertEqual(e.tint, .orange)
        XCTAssertFalse(try XCTUnwrap(m.node(.adapter)).isActive)
        XCTAssertEqual(m.node(.adapter)?.caption, "Fiş yok")
    }

    func testSupplementingWhenAdapterIsWeakUnderHeavyLoad() throws {
        var r = charging
        r.isCharging = false; r.amperageMA = -1_800
        r.systemPowerMW = 30_000; r.batteryPowerMW = -12_000; r.systemLoadMW = 42_000
        let m = PowerFlowModel.make(r)
        XCTAssertEqual(m.mode, .pluggedSupplementing)
        XCTAssertEqual(Set(m.edges.map(\.kind)), [.adapterToMac, .batteryToMac])
        XCTAssertEqual(m.edge(.adapterToMac)?.watts ?? 0, 30, accuracy: 0.01)
        XCTAssertEqual(m.edge(.batteryToMac)?.watts ?? 0, 12, accuracy: 0.01)
        XCTAssertEqual(m.edge(.batteryToMac)?.tint, .orange)
    }

    func testDevicesDrawFromMacNotAdapter() throws {
        var r = charging
        r.accessories = [phone, PowerPortAccessory(id: "port.USB‑C 4", name: "Harici ekran", kind: .display, portName: "USB‑C 4",
                                                    detail: "Realtek · DisplayPort", allocatedMW: nil, isDisplayOnly: true)]
        let m = PowerFlowModel.make(r)
        let dev = m.deviceEdges
        XCTAssertEqual(dev.count, 2)
        XCTAssertTrue(dev.allSatisfy { $0.from == .mac })
        // Ayrılan güç olan: yaklaşık ve aktif; olmayan: bilinmiyor, durağan gri.
        let known = try XCTUnwrap(dev.first { $0.to == .device("usb.1") })
        XCTAssertTrue(known.isApproximate); XCTAssertTrue(known.isActive)
        XCTAssertEqual(known.label, "≈2,5 W")
        let unknown = try XCTUnwrap(dev.first { $0.to == .device("port.USB‑C 4") })
        XCTAssertNil(unknown.watts); XCTAssertFalse(unknown.isActive); XCTAssertEqual(unknown.label, "?"); XCTAssertEqual(unknown.tint, .gray)
        XCTAssertTrue(unknown.tooltip.contains("Yalnız görüntü"))
        // Mac düğümü aksesuar gücünü yeniden saymaz.
        XCTAssertEqual(m.edge(.adapterToMac)?.watts ?? 0, 13.9, accuracy: 0.01)
        XCTAssertEqual(m.nodes.count, 5)
    }

    func testDeviceLimitAndOverflowCaption() {
        var r = charging
        r.accessories = (0..<4).map { PowerPortAccessory(id: "usb.\($0)", name: "Aygıt \($0)", kind: .other, portName: "USB", detail: "", allocatedMW: nil) }
        let m = PowerFlowModel.make(r)
        XCTAssertEqual(m.deviceEdges.count, PowerFlowModel.maxDevices)
        XCTAssertTrue(m.nodes.last?.caption.contains("+2") == true)
    }

    // MARK: Yedekler

    func testMacLoadFallbacksWithoutSystemLoad() throws {
        var r = charging
        r.systemLoadMW = nil // SystemPowerIn − şarj = 52,3 − 38,4
        XCTAssertEqual(PowerFlowModel.make(r).edge(.adapterToMac)?.watts ?? 0, 13.9, accuracy: 0.01)
        var b = onBattery
        b.systemLoadMW = nil // |BatteryPower|
        XCTAssertEqual(PowerFlowModel.make(b).edge(.batteryToMac)?.watts ?? 0, 15.8, accuracy: 0.01)
    }

    func testBatteryPowerFallsBackToVoltageTimesAmps() {
        var r = charging
        r.batteryPowerMW = nil; r.voltageMV = 12_930; r.amperageMA = 2_950
        XCTAssertEqual(PowerFlowModel.signedBatteryWatts(r), 38.14, accuracy: 0.05)
        r.isCharging = false; r.voltageMV = 12_000; r.amperageMA = -1_000
        XCTAssertEqual(PowerFlowModel.signedBatteryWatts(r), -12, accuracy: 0.05)
    }

    func testAdapterOutFallsBackToVoltageTimesCurrent() {
        var r = charging
        r.systemPowerMW = nil; r.systemVoltageInMV = 20_000; r.systemCurrentInMA = 1_800
        XCTAssertEqual(PowerFlowModel.adapterOutWatts(r) ?? 0, 36, accuracy: 0.01)
    }

    func testNoTelemetryAtAllStillProducesModel() {
        var r = BatteryReading.sampleCharging
        r.systemPowerMW = nil; r.batteryPowerMW = nil; r.systemLoadMW = nil; r.voltageMV = nil; r.amperageMA = nil
        let m = PowerFlowModel.make(r)
        XCTAssertEqual(m.edge(.adapterToMac)?.label, "?")
        XCTAssertFalse(m.hasMotion)
        XCTAssertFalse(m.summary.isEmpty)
    }

    func testIdleThresholdStopsTinyBatteryFlow() {
        var r = full
        r.batteryPowerMW = 200; r.isCharging = false; r.amperageMA = 10
        XCTAssertEqual(PowerFlowModel.make(r).mode, .pluggedIdle, "0,2 W pil akışı kenar oluşturmaz")
    }

    // MARK: Tooltip ve biçim

    func testAdapterTooltipHasVoltageCurrentAndEfficiency() throws {
        let tip = try XCTUnwrap(PowerFlowModel.make(charging).node(.adapter)).tooltip
        XCTAssertTrue(tip.contains("70W USB-C Power Adapter"), tip)
        XCTAssertTrue(tip.contains("20,0 V"), tip)
        XCTAssertTrue(tip.contains("3,39 A"), tip)
        XCTAssertTrue(tip.contains("verim %96"), tip) // 52,3 / (52,3 + 2,1)
        XCTAssertEqual(PowerFlowModel.make(charging).node(.adapter)?.value, "70 W")
    }

    func testFormattingOfNodesAndLabels() {
        let m = PowerFlowModel.make(charging)
        XCTAssertEqual(m.node(.mac)?.value, "14 W")
        XCTAssertEqual(m.node(.battery)?.value, "%64")
        XCTAssertEqual(m.edge(.adapterToBattery)?.label, "38 W")
        XCTAssertEqual(PowerFlowModel.volts(20_204), "20,2 V")
        XCTAssertEqual(PowerFlowModel.amps(3_390), "3,39 A")
        var small = full; small.systemLoadMW = 9_400; small.systemPowerMW = 9_400
        XCTAssertEqual(PowerFlowModel.make(small).edge(.adapterToMac)?.label, "9,4 W")
    }

    // MARK: Ölçek

    func testLogScaleIsMonotonicAndClamped() {
        var last = -1.0
        for w in [0.0, 0.5, 1, 3, 10, 30, 70, 100, 240] {
            let n = FlowScale.norm(watts: w)
            XCTAssertGreaterThanOrEqual(n, last); XCTAssertLessThanOrEqual(n, 1); last = n
        }
        XCTAssertEqual(FlowScale.norm(watts: 0), 0)
        XCTAssertEqual(FlowScale.norm(watts: 100), 1, accuracy: 1e-9)
        XCTAssertEqual(FlowScale.norm(watts: 500), 1)
        XCTAssertEqual(FlowScale.norm(watts: -5), 0)
        XCTAssertGreaterThan(FlowScale.speed(watts: 60), FlowScale.speed(watts: 5))
        XCTAssertGreaterThan(FlowScale.thickness(watts: 60), FlowScale.thickness(watts: 5))
        // Log: 1 W → 10 W farkı, 60 → 69 W farkından çok daha büyük.
        XCTAssertGreaterThan(FlowScale.norm(watts: 10) - FlowScale.norm(watts: 1), FlowScale.norm(watts: 69) - FlowScale.norm(watts: 60))
    }

    func testInactiveEdgesDoNotMove() {
        var r = full; r.systemLoadMW = 100; r.systemPowerMW = 100
        let e = PowerFlowModel.make(r).edge(.adapterToMac)
        XCTAssertEqual(e?.isActive, false); XCTAssertEqual(e?.speed, 0); XCTAssertEqual(e?.tint, .gray)
    }

    // MARK: Geometri ve saat

    func testCurvesRunFromSourceToSink() throws {
        let m = PowerFlowModel.make(charging)
        let toMac = try XCTUnwrap(PowerFlowGeometry.curve(for: try XCTUnwrap(m.edge(.adapterToMac)), in: m, width: 500))
        XCTAssertLessThan(toMac.p0.x, toMac.p3.x, "adaptör solda, Mac ortada")
        XCTAssertGreaterThan(toMac.tangent(0.5).dx, 0)
        let toBat = try XCTUnwrap(PowerFlowGeometry.curve(for: try XCTUnwrap(m.edge(.adapterToBattery)), in: m, width: 500))
        XCTAssertGreaterThan(toBat.p3.y, toBat.p0.y, "pil adaptörün altında")
        let b = PowerFlowModel.make(onBattery)
        let up = try XCTUnwrap(PowerFlowGeometry.curve(for: try XCTUnwrap(b.edge(.batteryToMac)), in: b, width: 500))
        XCTAssertLessThan(up.tangent(0.5).dy, 0, "pil → Mac yukarı")
    }

    func testClockIntegratesSpeedWithoutJumps() throws {
        let e = try XCTUnwrap(PowerFlowModel.make(charging).edge(.adapterToMac))
        let clock = FlowClock()
        let t0 = Date(timeIntervalSince1970: 1_000)
        clock.advance(to: t0, edges: [e])
        clock.advance(to: t0.addingTimeInterval(1.0 / 30), edges: [e])
        let p1 = try XCTUnwrap(clock.phases[e.id])
        XCTAssertEqual(p1, e.speed / 30, accuracy: 1e-3)
        // Uzun duraklama (pencere gizliydi): faz en çok 0,1 sn ilerler.
        clock.advance(to: t0.addingTimeInterval(500), edges: [e])
        let p2 = clock.phases[e.id] ?? 0
        let moved = (p2 - p1).truncatingRemainder(dividingBy: e.dotSpacing)
        XCTAssertLessThanOrEqual(abs(moved), e.speed * 0.1 + e.dotSpacing + 1e-6)
        clock.pause()
        clock.advance(to: t0.addingTimeInterval(600), edges: [e])
        XCTAssertEqual(clock.phases[e.id] ?? 0, p2, accuracy: 1e-9, "pause sonrası ilk kare dt = 0")
    }

    // MARK: Ayrıştırma

    func testParserReadsTelemetryAndAdapterContract() {
        let registry: [String: Any] = [
            "ExternalConnected": true, "IsCharging": false, "FullyCharged": true, "InstantAmperage": 0, "Voltage": 12_870,
            "PowerTelemetryData": ["SystemPowerIn": 36_439, "BatteryPower": 0, "SystemLoad": 36_439, "AdapterEfficiencyLoss": 948,
                                   "SystemVoltageIn": 20_204, "SystemCurrentIn": 1_803],
            "AdapterDetails": ["Watts": 68, "Name": "70W USB-C Power Adapter ", "Description": "pd charger", "AdapterVoltage": 20_000, "Current": 3_390,
                               "IsWireless": false],
        ]
        let r = AppleSmartBatteryParser.parse(registry: registry, powerSource: ["Current Capacity": 100, "Max Capacity": 100])
        XCTAssertEqual(r.systemLoadMW, 36_439); XCTAssertEqual(r.adapterEfficiencyLossMW, 948)
        XCTAssertEqual(r.systemVoltageInMV, 20_204); XCTAssertEqual(r.systemCurrentInMA, 1_803)
        XCTAssertEqual(r.adapterVoltageMV, 20_000); XCTAssertEqual(r.adapterCurrentMA, 3_390)
        XCTAssertEqual(PowerFlowModel.make(r).mode, .pluggedIdle)
    }

    func testAccessoryParserPortsAndUSBDevices() {
        let adapterPort: [String: Any] = ["ConnectionActive": true, "_adapterSource": true, "PortTypeDescription": "MagSafe 3", "Description": "Port-MagSafe 3@1"]
        let monitor: [String: Any] = ["ConnectionActive": true, "PortTypeDescription": "USB-C", "Description": "Port-USB-C@4", "SOPMfgString": "Realtek",
                                      "TransportsActive": ["CC", "DisplayPort"]]
        let idle: [String: Any] = ["ConnectionActive": false, "PortTypeDescription": "USB-C", "Description": "Port-USB-C@1"]
        let a = PowerPortAccessoryParser.parse(ports: [adapterPort, monitor, idle], usbDevices: [])
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a.first?.kind, .display); XCTAssertEqual(a.first?.portName, "USB‑C 4"); XCTAssertTrue(a.first?.isDisplayOnly == true)
        XCTAssertEqual(a.first?.detail, "Realtek · DisplayPort"); XCTAssertNil(a.first?.allocatedMW)
        XCTAssertEqual(PowerPortAccessoryParser.portName("Port-MagSafe 3@1"), "MagSafe 3")

        let usb: [[String: Any]] = [["USB Product Name": "iPhone", "USB Vendor Name": "Apple Inc.", "locationID": 0x0100_0000, "UsbPowerSinkAllocation": 500],
                                    ["USB Product Name": "Portable SSD T7", "locationID": 0x0200_0000]]
        let b = PowerPortAccessoryParser.parse(ports: [adapterPort], usbDevices: usb)
        XCTAssertEqual(b.map(\.kind), [.phone, .storage])
        XCTAssertEqual(b[0].allocatedMW, 2_500, "500 mA × 5 V")
        XCTAssertNil(b[1].allocatedMW)
        // Veri yolu olan port, USB aygıtı listelendiğinde tekrar sayılmaz.
        var usbPort = monitor; usbPort["TransportsActive"] = ["CC", "USB2", "USB3"]
        XCTAssertEqual(PowerPortAccessoryParser.parse(ports: [usbPort], usbDevices: usb).count, 2)
    }
}
