import XCTest
@testable import Adalmon

final class SMCReaderTests: XCTestCase {
    func testOpensAndReadsGPUTemperature() throws {
        guard let smc = SMCReader() else {
            throw XCTSkip("AppleSMC açılamadı (VM ya da izin yok)")
        }
        let count = try XCTUnwrap(smc.keyCount(), "#KEY okunamadı")
        print("SMC key count: \(count)")

        let discovered = smc.discoveredGPUKeys()
        for key in discovered {
            print("SMC discovered \(key) = \(smc.readFloat(key).map { String(format: "%.2f", $0) } ?? "nil")")
        }
        let discoveryStart = ContinuousClock.now
        let keys = smc.gpuTemperatureKeys
        print("SMC GPU key discovery: \(ContinuousClock.now - discoveryStart), discovered=\(discovered.count), selected=\(keys)")
        guard !keys.isEmpty else {
            // M1/M2/M3'te GPU sıcaklığı IOHID "GPU MTR Temp Sensor" ile gelir; "Tg" flt anahtarı olmayabilir.
            throw XCTSkip("Bu makinede 'Tg' önekli flt SMC anahtarı yok")
        }

        _ = smc.gpuTemperatures() // ısınma
        var durations: [Duration] = []
        var last: [String: Double] = [:]
        for _ in 0..<20 {
            let start = ContinuousClock.now
            last = smc.gpuTemperatures()
            durations.append(ContinuousClock.now - start)
        }
        durations.sort()
        let median = durations[durations.count / 2]
        for (key, value) in last.sorted(by: { $0.key < $1.key }) {
            print("SMC \(key) = \(String(format: "%.2f", value))")
        }
        print("SMC gpuTemperatures() median=\(median) min=\(durations[0]) max=\(durations[durations.count - 1]) for \(keys.count) keys")
        XCTAssertFalse(last.isEmpty)
        // Gevşek sınır: hedef < 2 ms, ama paralel derlemeler makineyi yükleyebilir.
        XCTAssertLessThan(median, .milliseconds(10))

        let stats = try XCTUnwrap(TemperatureSampler().sample())
        let gpu = try XCTUnwrap(stats.gpu, "TemperatureSampler GPU sıcaklığı vermedi")
        print("SMC TemperatureSampler gpu=\(String(format: "%.2f", gpu)) cpu=\(String(describing: stats.cpu))")
        XCTAssertTrue((10.0...110.0).contains(gpu), "GPU \(gpu) °C makul aralıkta değil")
    }

    func testDecodeFloatLittleEndian() {
        let bytes = withUnsafeBytes(of: Float(59.0).bitPattern.littleEndian) { Array($0) }
        XCTAssertEqual(SMCReader.decode(bytes: bytes, type: SMCReader.typeFloat), 59.0)
        XCTAssertNil(SMCReader.decode(bytes: [0, 0], type: SMCReader.typeFloat))
    }

    func testDecodeSP78() {
        XCTAssertEqual(SMCReader.decode(bytes: [0x3B, 0x80], type: SMCReader.typeSP78), 59.5)
        XCTAssertEqual(SMCReader.decode(bytes: [0xFF, 0x00], type: SMCReader.typeSP78), -1.0)
        XCTAssertNil(SMCReader.decode(bytes: [1, 2, 3, 4], type: SMCReader.typeUInt32))
    }

    func testSelectGPUKeysPrefersBestMatchingStatsTable() {
        let m4 = ["Tg0C", "Tg0D", "Tg0G", "Tg0H", "Tg0K", "Tg0L", "Tg0O", "Tg0P", "Tg0U", "Tg0V",
                  "Tg0X", "Tg0Y", "Tg0d", "Tg0e", "Tg0j", "Tg0k", "Tg0m", "Tg0n"]
        XCTAssertEqual(SMCReader.selectGPUKeys(discovered: m4), ["Tg0G", "Tg0H", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"])
        XCTAssertEqual(SMCReader.selectGPUKeys(discovered: ["Tg0a", "Tg0b"]), ["Tg0a", "Tg0b"])
        XCTAssertEqual(SMCReader.selectGPUKeys(discovered: []), [])
    }

    func testFourCCRoundTrip() {
        XCTAssertEqual(SMCReader.fourCC("flt "), 0x666C_7420)
        XCTAssertEqual(SMCReader.string(fromFourCC: SMCReader.fourCC("Tg0G")), "Tg0G")
    }

    func testMergeAddsSMCGPUOnlyWhenHIDHasNone() {
        let hid = TemperatureSampler.classify(["PMU tdie1": 50, "NAND CH0 temp": 30])
        let merged = TemperatureSampler.merge(hid, smcGPU: ["Tg0G": 50, "Tg0H": 60, "Tg0X": 500])
        XCTAssertEqual(merged?.gpu, 55)
        XCTAssertEqual(merged?.cpu, 50, "CPU IOHID'den kalmalı")
        XCTAssertEqual(merged?.sensors["SMC Tg0G"], 50)
        XCTAssertNil(merged?.sensors["SMC Tg0X"])

        let withHIDGPU = TemperatureSampler.classify(["PMU tdie1": 50, "GPU MTR Temp Sensor1": 40])
        XCTAssertEqual(TemperatureSampler.merge(withHIDGPU, smcGPU: ["Tg0G": 80])?.gpu, 40)

        XCTAssertEqual(TemperatureSampler.merge(nil, smcGPU: ["Tg0G": 45])?.gpu, 45)
        XCTAssertNil(TemperatureSampler.merge(nil, smcGPU: [:]))
        XCTAssertEqual(TemperatureSampler.merge(hid, smcGPU: [:]), hid)
    }
}
