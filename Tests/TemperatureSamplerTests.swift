import XCTest
@testable import Adalmon

final class TemperatureSamplerTests: XCTestCase {
    func testReadsPlausibleCPUTemperature() throws {
        let sampler = TemperatureSampler()
        let start = ContinuousClock.now
        let stats = try XCTUnwrap(sampler.sample(), "Sensör bulunamadı")
        let elapsed = ContinuousClock.now - start

        print("TEMP first read: \(elapsed)")
        for (name, value) in stats.sensors.sorted(by: { $0.key < $1.key }) {
            print("TEMP sensor \(name) = \(value)")
        }
        print("TEMP cpu=\(String(describing: stats.cpu)) max=\(String(describing: stats.cpuMax)) gpu=\(String(describing: stats.gpu)) ssd=\(String(describing: stats.ssd)) battery=\(String(describing: stats.battery))")

        let cpu = try XCTUnwrap(stats.cpu)
        XCTAssertTrue((10.0...110.0).contains(cpu))

        // Önbellek: 5 sn içinde aynı değer döner.
        XCTAssertEqual(sampler.sample(), stats)
    }

    func testSteadyStateReadIsCheap() {
        let hid = HIDTemperatureSensors(isRelevant: TemperatureSampler.isRelevantSensor)
        _ = hid.readAll()
        let start = ContinuousClock.now
        let values = hid.readAll()
        let elapsed = ContinuousClock.now - start
        print("TEMP steady-state read: \(elapsed) for \(values.count) sensors")
        XCTAssertFalse(values.isEmpty)
    }

    func testClassifyIgnoresImplausibleValues() {
        let stats = TemperatureSampler.classify(["PMU tdie1": 50, "PMU tdie2": 60, "GPU MTR Temp Sensor1": 200, "NAND CH0 temp": 30])
        XCTAssertEqual(stats?.cpu, 55)
        XCTAssertEqual(stats?.cpuMax, 60)
        XCTAssertNil(stats?.gpu)
        XCTAssertEqual(stats?.ssd, 30)
        XCTAssertNil(TemperatureSampler.classify(["PMU tdie1": 0]))
    }
}
