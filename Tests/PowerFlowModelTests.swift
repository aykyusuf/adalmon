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

    func testPowerSinkingDeviceIsNodeAndDisplayOnlyIsChip() throws {
        var r = charging
        r.accessories = [phone, PowerPortAccessory(id: "port.USB‑C 4", name: "Harici ekran", kind: .display, portName: "USB‑C 4",
                                                    detail: "Realtek · DisplayPort", allocatedMW: nil, isDisplayOnly: true)]
        let m = PowerFlowModel.make(r)
        // Yalnız ayrılan gücü bilinen aygıt düğüm + kenar olur; "?" kenarı yok.
        let dev = m.deviceEdges
        XCTAssertEqual(dev.count, 1)
        XCTAssertTrue(dev.allSatisfy { $0.from == .mac })
        let known = try XCTUnwrap(dev.first { $0.to == .device("usb.1") })
        XCTAssertTrue(known.isApproximate); XCTAssertTrue(known.isActive)
        XCTAssertEqual(known.label, "≈2,5 W")
        XCTAssertFalse(m.edges.contains { $0.label == "?" })
        XCTAssertNil(m.node(.device("port.USB‑C 4")), "görüntü-yalnız aksesuar düğüm değil")
        XCTAssertEqual(m.nodes.count, 4)
        // Görüntü-yalnız aksesuar diyagramın altında çip.
        let chip = try XCTUnwrap(m.chips.first)
        XCTAssertEqual(m.chips.count, 1)
        XCTAssertEqual(chip.title, "Harici ekran · USB‑C 4")
        XCTAssertEqual(chip.symbol, "display")
        XCTAssertTrue(chip.tooltip.contains("Yalnız görüntü"))
        XCTAssertTrue(m.summary.contains("Harici ekran"))
        // Mac düğümü aksesuar gücünü yeniden saymaz.
        XCTAssertEqual(m.edge(.adapterToMac)?.watts ?? 0, 13.9, accuracy: 0.01)
    }

    func testDeviceWithUnknownDrawIsChipNotNode() {
        var r = charging
        r.accessories = [PowerPortAccessory(id: "usb.9", name: "Portable SSD", kind: .storage, portName: "USB", detail: "USB", allocatedMW: nil)]
        let m = PowerFlowModel.make(r)
        XCTAssertTrue(m.deviceEdges.isEmpty)
        XCTAssertEqual(m.nodes.count, 3)
        XCTAssertEqual(m.chips.map(\.title), ["Portable SSD · USB"])
        XCTAssertFalse(m.edges.contains { $0.label == "?" })
        XCTAssertFalse(m.hasDeviceNodes)
    }

    func testDeviceLimitAndOverflowCaption() {
        var r = charging
        r.accessories = (0..<4).map { PowerPortAccessory(id: "usb.\($0)", name: "Aygıt \($0)", kind: .other, portName: "USB", detail: "", allocatedMW: 1_500) }
        let m = PowerFlowModel.make(r)
        XCTAssertEqual(m.deviceEdges.count, PowerFlowModel.maxDevices)
        XCTAssertTrue(m.nodes.last?.caption.contains("+2") == true)
        XCTAssertTrue(m.chips.isEmpty)
    }

    // MARK: Pil rengi ve düzen

    func testBatteryTintByState() {
        XCTAssertEqual(PowerFlowModel.make(charging).node(.battery)?.tint, .green)
        XCTAssertEqual(PowerFlowModel.make(charging).node(.battery)?.isCharging, true)
        XCTAssertEqual(PowerFlowModel.make(full).node(.battery)?.tint, .green)
        XCTAssertEqual(PowerFlowModel.make(full).node(.battery)?.isCharging, false)
        var low = onBattery; low.level = 18
        XCTAssertEqual(PowerFlowModel.make(low).node(.battery)?.tint, .orange)
        var critical = onBattery; critical.level = 6
        XCTAssertEqual(PowerFlowModel.make(critical).node(.battery)?.tint, .red)
        XCTAssertEqual(PowerFlowModel.make(onBattery).node(.battery)?.tint, .green)
        XCTAssertEqual(PowerFlowModel.make(full).node(.battery)?.value, "%100")
        XCTAssertEqual(PowerFlowModel.make(full).node(.battery)?.caption, "dolu")
    }

    private func modelWithDevices(_ count: Int, base: BatteryReading? = nil) -> PowerFlowModel {
        var r = base ?? charging
        r.accessories = (0..<count).map { PowerPortAccessory(id: "usb.\($0)", name: "Aygıt \($0)", kind: .other, portName: "USB‑C \($0 + 2)", detail: "", allocatedMW: 4_000) }
        return PowerFlowModel.make(r)
    }

    func testGridLayoutIsBalanced() throws {
        for width in [CGFloat(320), 344, 640] {
            let m = modelWithDevices(2)
            func c(_ id: FlowNodeID) throws -> CGPoint { PowerFlowGeometry.center(try XCTUnwrap(m.node(id)), in: m, width: width) }
            let adapter = try c(.adapter), mac = try c(.mac), bat = try c(.battery), d0 = try c(.device("usb.0")), d1 = try c(.device("usb.1"))
            XCTAssertEqual(mac.x, width / 2, accuracy: 0.01)
            XCTAssertLessThan(adapter.x, mac.x); XCTAssertEqual(adapter.y, mac.y)
            XCTAssertEqual(bat.x, mac.x, "pil Mac'in hemen altında"); XCTAssertGreaterThan(bat.y, mac.y)
            XCTAssertGreaterThan(d0.x, mac.x); XCTAssertEqual(d0.x, d1.x); XCTAssertEqual(d0.y, mac.y); XCTAssertEqual(d1.y, bat.y)
            XCTAssertEqual(mac.x - adapter.x, d0.x - mac.x, accuracy: 0.01, "simetrik")
            let r = PowerFlowGeometry.nodeRadius
            for p in [adapter, mac, bat, d0, d1] { XCTAssertGreaterThanOrEqual(p.x - r, 0); XCTAssertLessThanOrEqual(p.x + r, width) }
        }
    }

    func testGroupIsCenteredWithoutDevices() throws {
        for width in [CGFloat(320), 344, 640] {
            let m = PowerFlowModel.make(charging)
            let xs = try [FlowNodeID.adapter, .mac, .battery].map { PowerFlowGeometry.center(try XCTUnwrap(m.node($0)), in: m, width: width).x }
            let r = PowerFlowGeometry.nodeRadius
            XCTAssertEqual(((xs.min() ?? 0) - r + (xs.max() ?? 0) + r) / 2, width / 2, accuracy: 0.01)
            XCTAssertEqual(xs[1], xs[2], accuracy: 0.01, "pil Mac'in altında")
        }
    }

    /// Hiçbir kenar etiketi bir düğümün dairesine ya da başka bir etikete binmez (tüm modlar, panel ve sayfa genişliği).
    func testEdgeLabelsNeverOverlapNodes() throws {
        var supp = charging
        supp.isCharging = false; supp.amperageMA = -1_800
        supp.systemPowerMW = 30_000; supp.batteryPowerMW = -12_000; supp.systemLoadMW = 42_000
        let models = [PowerFlowModel.make(charging), PowerFlowModel.make(full), PowerFlowModel.make(onBattery), PowerFlowModel.make(supp),
                      modelWithDevices(1), modelWithDevices(2), modelWithDevices(2, base: onBattery), modelWithDevices(2, base: supp)]
        for width in [CGFloat(320), 344, 640] {
            for m in models {
                var boxes: [CGRect] = []
                for e in m.edges {
                    let curve = try XCTUnwrap(PowerFlowGeometry.curve(for: e, in: m, width: width))
                    let p = PowerFlowGeometry.labelCenter(for: curve)
                    let box = CGRect(x: p.x - 27, y: p.y - 9, width: 54, height: 18)
                    for n in m.nodes {
                        let c = PowerFlowGeometry.center(n, in: m, width: width), r = PowerFlowGeometry.nodeRadius
                        XCTAssertFalse(box.intersects(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), "\(e.id) etiketi \(n.id) üstüne biniyor (w=\(width))")
                    }
                    for o in boxes { XCTAssertFalse(box.intersects(o), "etiketler çakışıyor (w=\(width))") }
                    boxes.append(box)
                    XCTAssertGreaterThanOrEqual(box.minX, 0); XCTAssertLessThanOrEqual(box.maxX, width)
                }
            }
        }
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
        XCTAssertGreaterThan(toBat.p3.x, toBat.p0.x, "adaptör → pil: aşağı ve sağa")
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
