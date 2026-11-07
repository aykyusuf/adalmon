import XCTest
@testable import Adalmon

/// Metrik panel içerik modelleri (saf kurucular) ve süreç sıralaması.
@MainActor
final class MetricPanelModelTests: XCTestCase {
    private let data = PanelData.metricSample

    func testCPUModelCoresLoadAndTemperatures() {
        let m = CPUPanelModel.make(data, processes: PanelData.metricProcesses)
        XCTAssertEqual(m.bigValue, "%33")
        XCTAssertEqual(m.userText, "%22"); XCTAssertEqual(m.systemText, "%11")
        XCTAssertEqual(m.cores.count, 10)
        XCTAssertEqual(m.cores.prefix(4).map(\.label), ["E1", "E2", "E3", "E4"])
        XCTAssertEqual(m.cores.suffix(6).map(\.label), ["P1", "P2", "P3", "P4", "P5", "P6"])
        XCTAssertTrue(m.cores[0].isEfficiency); XCTAssertFalse(m.cores[9].isEfficiency)
        XCTAssertEqual(m.loadAverages, ["3,42", "2,87", "2,31"])
        XCTAssertEqual(m.temperatureAverage, "44 °C"); XCTAssertEqual(m.temperatureMax, "53 °C")
        XCTAssertEqual(m.topologyText, "6 P + 4 E çekirdek")
        XCTAssertEqual(m.series.values.count, 60)
        XCTAssertEqual(m.processes.count, 5)
    }

    func testModelsWithoutSnapshotDegradeGracefully() {
        let empty = PanelData()
        let cpu = CPUPanelModel.make(empty, processes: [])
        XCTAssertFalse(cpu.hasData); XCTAssertTrue(cpu.cores.isEmpty); XCTAssertNil(cpu.temperatureAverage)
        XCTAssertFalse(MemoryPanelModel.make(empty, processes: []).hasData)
        XCTAssertFalse(TemperaturePanelModel.make(empty).hasData)
        XCTAssertFalse(DiskPanelModel.make(empty, writers: []).hasData)
        XCTAssertTrue(GPUPanelModel.make(empty, processes: []).series.isEmpty)
    }

    func testGPUModelDistinguishesRealLoadFromBusyTime() {
        let m = GPUPanelModel.make(data, processes: [])
        XCTAssertEqual(m.loadText, "%11"); XCTAssertEqual(m.busyText, "%28"); XCTAssertEqual(m.bigValue, "%11")
        XCTAssertEqual(m.frequencyText, "0,9 GHz")
        XCTAssertEqual(try XCTUnwrap(m.frequencyFraction), 920.0 / 1578.0, accuracy: 0.001)
        XCTAssertEqual(m.temperature, "41 °C")
    }

    func testMemoryModelPressureAndBreakdown() {
        var d = data
        let normal = MemoryPanelModel.make(d, processes: [])
        XCTAssertEqual(normal.pressure, .normal)
        XCTAssertEqual(normal.parts.map(\.id), ["app", "wired", "compressed", "cache"])
        XCTAssertEqual(normal.swapFraction, 0.25, accuracy: 0.001)
        d.snapshot?.memory.pressure = .critical
        XCTAssertEqual(MemoryPanelModel.make(d, processes: []).pressure, .critical)
        d.snapshot?.memory.pressure = .warning
        XCTAssertEqual(MemoryPanelModel.make(d, processes: []).pressure, .warning)
        XCTAssertGreaterThan(MemoryPanelModel.Pressure.critical.level, MemoryPanelModel.Pressure.warning.level)
    }

    func testDiskNetworkAndTemperatureModels() {
        let disk = DiskPanelModel.make(data, writers: [])
        XCTAssertTrue(disk.freeText.hasSuffix("GB")); XCTAssertEqual(disk.readSeries.values.count, 60)
        let net = NetworkPanelModel.make(data)
        XCTAssertEqual(net.connectionTitle, "Wi-Fi"); XCTAssertEqual(net.downSeries.values.count, 60)
        let temp = TemperaturePanelModel.make(data)
        XCTAssertEqual(temp.headline, "44 °C")
        XCTAssertEqual(temp.groups.map(\.source), [.cpu, .cpuMax, .gpu, .ssd, .battery])
        XCTAssertEqual(temp.sensors.first?.name, "PMU tdie4", "en sıcak sensör üstte")
    }

    func testTopProcessBuilderRanksFiltersAndNames() {
        func group(_ key: String, cpuMs: UInt64 = 0, gpuMs: UInt64 = 0, footprintMB: UInt64 = 0) -> LiveGroup {
            LiveGroup(key: key, usage: ResourceUsage(cpuNs: cpuMs * 1_000_000, gpuNs: gpuMs * 1_000_000, footprint: footprintMB * 1_000_000),
                      processCount: 1, pids: [1], members: [])
        }
        // 2 sn, 10 çekirdek: 1000 ms CPU = %5 makine.
        let snap = LiveSnapshot(groups: [group("/A.app", cpuMs: 1000, gpuMs: 100, footprintMB: 200), group("/B.app", cpuMs: 4000, gpuMs: 600, footprintMB: 900),
                                         group("/C.app", cpuMs: 1, footprintMB: 50), group(ResourceKeys.system, cpuMs: 9000, footprintMB: 5000)],
                                elapsed: 2, totalProcessCount: 4)
        let cpu = TopProcessBuilder.top(snap, metric: .cpu, cores: 10) { $0.replacingOccurrences(of: "/", with: "") }
        XCTAssertEqual(cpu.map(\.name), ["B.app", "A.app"], "sistem kovası ve ihmal edilebilir değerler elenir")
        XCTAssertEqual(cpu[0].valueText, "%20"); XCTAssertEqual(cpu[0].fraction, 1, accuracy: 0.001)
        XCTAssertEqual(cpu[1].valueText, "%5,0")
        let gpu = TopProcessBuilder.top(snap, metric: .gpu, cores: 10) { $0 }
        XCTAssertEqual(gpu.first?.key, "/B.app"); XCTAssertEqual(gpu.first?.valueText, "%30")
        let mem = TopProcessBuilder.top(snap, metric: .memory, cores: 10, limit: 2) { $0 }
        XCTAssertEqual(mem.map(\.key), ["/B.app", "/A.app"])
        XCTAssertEqual(TopProcessBuilder.top(LiveSnapshot(groups: snap.groups, elapsed: 0), metric: .cpu, cores: 10) { $0 }, [], "taban çizgisi örneği boş döner")
    }

    func testDiskWritersFiltersSpecialKeys() {
        let writers = TopProcessBuilder.writers([ResourceRank(app: ResourceKeys.other, value: 9e9), ResourceRank(app: "/X.app", value: 2e9),
                                                 ResourceRank(app: "/Y.app", value: 1e9)]) { $0 }
        XCTAssertEqual(writers.map(\.key), ["/X.app", "/Y.app"]); XCTAssertEqual(writers[1].fraction, 0.5, accuracy: 0.001)
    }

    func testSeriesReadoutFindsNearestSampleAndFormats() throws {
        let series = PanelSeries.make(values: data.cpuHistory, samples: data.samples, format: .percent)
        let end = try XCTUnwrap(series.readout(atFraction: 1))
        XCTAssertEqual(end.index, 59); XCTAssertTrue(end.text.hasPrefix("şimdi · %"))
        let mid = try XCTUnwrap(series.readout(atFraction: 0.5))
        XCTAssertEqual(Double(mid.index), 29.5, accuracy: 1.1)
        XCTAssertTrue(mid.text.contains("sn önce"))
        XCTAssertEqual(PanelSeries(values: [1_500_000], times: [.now], format: .rate).text(1_500_000), "1,5 MB/s")
        XCTAssertNil(PanelSeries(values: [], times: [], format: .rate).readout(atFraction: 0.5))
    }

    func testBatteryModelDischargingChargingAndFull() {
        let now = Date()
        let d = BatteryPanelModel.make(.sample, lastRefresh: now.addingTimeInterval(-180), now: now)
        XCTAssertEqual(d.level, 78); XCTAssertEqual(d.untilLabel, "BOŞALANA KADAR"); XCTAssertEqual(d.untilValue, "3:12")
        XCTAssertEqual(d.healthText, "%86"); XCTAssertEqual(d.healthWord, "İyi"); XCTAssertEqual(d.cyclesText, "178/1.000")
        XCTAssertEqual(d.celsiusText, "31,4 °C"); XCTAssertEqual(d.fahrenheitText, "88,5 °F")
        XCTAssertEqual(d.currentDirection, .discharging); XCTAssertEqual(d.chargingStateText, "Deşarj oluyor")
        XCTAssertEqual(d.updatedText, "3 dk önce"); XCTAssertEqual(d.remainingText, "4.003 mAh")
        XCTAssertEqual(d.chargerText, "—")
        let c = BatteryPanelModel.make(.sampleCharging, lastRefresh: now, now: now)
        XCTAssertEqual(c.untilLabel, "DOLANA KADAR"); XCTAssertEqual(c.untilValue, "0:40"); XCTAssertEqual(c.currentDirection, .charging)
        XCTAssertEqual(c.chargerText, "70 W"); XCTAssertEqual(c.cableText, "MagSafe"); XCTAssertEqual(c.updatedText, "az önce")
        var full = BatteryReading.sampleCharging
        full.level = 100; full.isCharging = false; full.isFullyCharged = true; full.amperageMA = 0; full.timeToFullMinutes = nil
        let f = BatteryPanelModel.make(full, lastRefresh: nil, now: now)
        XCTAssertEqual(f.untilValue, "∞"); XCTAssertEqual(f.statusTitle, "Tam şarjlı"); XCTAssertEqual(f.currentDirection, .idle)
        XCTAssertEqual(f.flowNote, "Pil dolu")
    }

    func testBatteryHealthWordsAndUpdatedText() {
        var r = BatteryReading.sample
        r.appleMaxCapacityPercent = 65
        XCTAssertEqual(BatteryPanelModel.make(r, lastRefresh: nil).healthWord, "Zayıf")
        r.appleMaxCapacityPercent = 75
        XCTAssertEqual(BatteryPanelModel.make(r, lastRefresh: nil).healthWord, "Orta")
        let now = Date()
        XCTAssertEqual(BatteryPanelModel.updatedText(now.addingTimeInterval(-7_300), now: now), "2 sa önce")
        XCTAssertEqual(BatteryPanelModel.updatedText(now.addingTimeInterval(-30), now: now), "30 sn önce")
    }
}
