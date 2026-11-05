import XCTest
@testable import Adalmon

final class GPUReportSamplerTests: XCTestCase {
    /// Bu makinenin (M4, Mac16,1) pmgr "voltage-states9" verisi.
    private static let m4Table = Data(hex: "000000007d000000807825146202000080eed5248002000000ff712fa802000000285037d5020000005ebe38070300000048f13e070300004081c33e3403000080c8bc45340300000020aa445c03000080bb2c4c5c0300000095c3477a0300008042c04f7a0300008027094fc5030000806b9e57c5030000805e0e5e1f040000")

    func testParsesM4FrequencyTableInOrder() {
        let table = GPUReportSampler.parseFrequencyTable(Self.m4Table)
        XCTAssertEqual(table.count, 16)
        XCTAssertEqual(table.first, 0)
        XCTAssertEqual(table[1], 338)
        XCTAssertEqual(table.last, 1_578)
        XCTAssertEqual(table.max(), 1_578)
    }

    func testWeightingMathWithFakeResidencies() throws {
        // OFF 50, 500 MHz'de 25, 1000 MHz'de 25 → aktif %50, ortalama 750 MHz, yük (25·500+25·1000)/(100·1000) = 0,375.
        let residencies: [(name: String, value: Int64)] = [("OFF", 50), ("P1", 25), ("P2", 0), ("P3", 25)]
        let m = try XCTUnwrap(GPUReportSampler.compute(residencies: residencies, frequenciesMHz: [0, 500, 750, 1_000]))
        XCTAssertEqual(m.activeResidency, 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.frequencyMHz), 750, accuracy: 1e-9)
        XCTAssertEqual(m.load, 0.375, accuracy: 1e-9)
        XCTAssertEqual(m.maxFrequencyMHz, 1_000)
    }

    func testFullSpeedIsFullLoadAndIdleHasNoFrequency() throws {
        let full = try XCTUnwrap(GPUReportSampler.compute(residencies: [("OFF", 0), ("P1", 0), ("P2", 10)], frequenciesMHz: [0, 400, 800]))
        XCTAssertEqual(full.load, 1, accuracy: 1e-9)
        XCTAssertEqual(full.activeResidency, 1, accuracy: 1e-9)

        let idle = try XCTUnwrap(GPUReportSampler.compute(residencies: [("OFF", 100), ("P1", 0), ("P2", 0)], frequenciesMHz: [0, 400, 800]))
        XCTAssertEqual(idle.load, 0)
        XCTAssertEqual(idle.activeResidency, 0)
        XCTAssertNil(idle.frequencyMHz)

        XCTAssertNil(GPUReportSampler.compute(residencies: [("OFF", 0), ("P1", 0)], frequenciesMHz: [0, 400]))
        XCTAssertNil(GPUReportSampler.compute(residencies: [("OFF", 1), ("P1", 1)], frequenciesMHz: []))
    }

    func testDisplayLoadAndPanelText() {
        var g = GPUStats(utilization: 0.31, rendererUtilization: nil, tilerUtilization: nil, memoryUsedBytes: nil)
        XCTAssertEqual(g.displayLoad, 0.31)
        XCTAssertEqual(SystemMetric.gpuBusyAndFrequency(g), "meşgul süre (Device Utilization)")
        g.load = 0.22
        g.frequencyMHz = 1_120
        XCTAssertEqual(g.displayLoad, 0.22)
        XCTAssertEqual(SystemMetric.gpuBusyAndFrequency(g), "meşgul %31 · 1,1 GHz")
        g.frequencyMHz = nil
        XCTAssertEqual(SystemMetric.gpuBusyAndFrequency(g), "meşgul %31")
    }

    func testLiveSamplesOnThisMachine() async throws {
        let sampler = GPUReportSampler()
        let accelerator = GPUSampler()
        let setupStart = ContinuousClock.now
        XCTAssertNil(sampler.sample(), "İlk çağrı taban örnek olmalı")
        let setup = ContinuousClock.now - setupStart

        var durations: [Duration] = []
        for _ in 0..<3 {
            try await Task.sleep(for: .seconds(1))
            let start = ContinuousClock.now
            let result = sampler.sample()
            durations.append(ContinuousClock.now - start)
            let m = try XCTUnwrap(result, "IOReport GPUPH okunamadı")
            let busy = accelerator.sample()?.utilization
            print(String(format: "GPU_REPORT: load=%.3f residency=%.3f freq=%@ MHz max=%.0f MHz ioaccel=%@",
                         m.load, m.activeResidency, m.frequencyMHz.map { String(format: "%.0f", $0) } ?? "nil",
                         m.maxFrequencyMHz, busy.map { String(format: "%.3f", $0) } ?? "nil"))
            XCTAssertTrue((0...1).contains(m.load))
            XCTAssertTrue((0...1).contains(m.activeResidency))
            XCTAssertLessThanOrEqual(m.load, m.activeResidency + 1e-9)
            XCTAssertTrue((300...2_000).contains(m.maxFrequencyMHz))
            if m.activeResidency > 0.01 {
                let f = try XCTUnwrap(m.frequencyMHz)
                XCTAssertTrue((300...2_000).contains(f), "frekans \(f) MHz")
            }
        }
        print("GPU_REPORT_TIMING: setup+first=\(setup) perCall=\(durations)")
        XCTAssertLessThan(durations.max() ?? .zero, .milliseconds(5))
    }
}

private extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}
