import XCTest
@testable import Adalmon

final class MetricsSamplerTests: XCTestCase {
    func testSamplesTwiceAndProducesSaneValues() async throws {
        let sampler = MetricsSampler()
        _ = sampler.sample()
        try await Task.sleep(for: .seconds(1))
        let snapshot = sampler.sample()
        print("SNAPSHOT: \(snapshot)")

        XCTAssertTrue((0...1).contains(snapshot.cpu.total))
        XCTAssertFalse(snapshot.cpu.perCore.isEmpty)
        XCTAssertGreaterThan(snapshot.memory.totalBytes, 0)
        XCTAssertLessThanOrEqual(snapshot.memory.usedBytes, snapshot.memory.totalBytes)
        XCTAssertGreaterThan(snapshot.disk.totalBytes, 0)
        XCTAssertFalse(snapshot.network.primaryInterface.isEmpty)
        XCTAssertFalse(snapshot.network.cumulativeIn.isEmpty)
        XCTAssertFalse(snapshot.network.cumulativeOut.isEmpty)
    }
}
