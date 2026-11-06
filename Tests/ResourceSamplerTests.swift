import XCTest
@testable import Adalmon

final class ResourceSamplerTests: XCTestCase {
    func testSweepProducesGroupsAndMeasuresCost() {
        let sweeper = ResourceSweeper()
        let first = sweeper.sweep()
        XCTAssertFalse(first.groups.isEmpty, "süreç listesi okunabilmeli")
        XCTAssertTrue(first.groups.values.allSatisfy { $0.usage.cpuNs == 0 }, "ilk süpürme taban çizgisi")
        // Test sürecinin kendi uygulaması bir grupta görünmeli ve bellek > 0.
        var burn = 0.0
        for i in 0..<3_000_000 { burn += sin(Double(i)) }
        XCTAssertTrue(burn != 0)
        let t0 = DispatchTime.now().uptimeNanoseconds
        let second = sweeper.sweep()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        print("SWEEP_MS", ms, "groups", second.groups.count, "coalitionAPI", second.usedCoalitionAPI)
        XCTAssertGreaterThan(second.groups.values.reduce(0) { $0 + $1.usage.footprint }, 0)
        XCTAssertGreaterThan(second.groups.values.reduce(0) { $0 + $1.usage.cpuNs }, 0, "test CPU yaktı")
        XCTAssertLessThan(ms, 100, "tek süpürme 100 ms altında olmalı")
        XCTAssertNotNil(VolumeSpace.freeBytes())
    }

    func testSweepCostBenchmark() {
        let sweeper = ResourceSweeper()
        _ = sweeper.sweep()
        let n = 20
        let t0 = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<n { _ = sweeper.sweep() }
        let perSweepMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6 / Double(n)
        let selectStart = DispatchTime.now().uptimeNanoseconds
        let r = sweeper.sweep()
        let rows = TopNUnion.select(r.groups.map { KeyedUsage(key: $0.key, usage: $0.value.usage) })
        let selectMs = Double(DispatchTime.now().uptimeNanoseconds - selectStart) / 1e6
        print("SWEEP_BENCH per-sweep ms:", perSweepMs, "sweep+select ms:", selectMs, "rows:", rows.count, "groups:", r.groups.count)
        XCTAssertLessThan(perSweepMs, 50)
    }

    func testTickWritesRowsToStore() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "tick-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UsageStore(path: dir.appending(path: "t.sqlite").path)
        let sampler = ResourceSampler(store: store)
        await sampler.tickNowAndWait() // taban
        var x = 0.0; for i in 0..<2_000_000 { x += cos(Double(i)) }
        XCTAssertTrue(x != 0)
        await sampler.tickNowAndWait()
        try await Task.sleep(for: .milliseconds(500)) // detached yazma
        let counts = await store.resourceRowCounts()
        XCTAssertGreaterThan(counts.minute, 0)
        let free = await store.diskFreeSeries(window: .hour1)
        XCTAssertFalse(free.isEmpty)
        let top = await store.topConsumers(metric: .memoryPeak, window: .hour1)
        XCTAssertFalse(top.isEmpty)
    }

    func testLiveSamplerReturnsRowsWithMembers() async throws {
        let live = LiveResourceSampler()
        let base = await live.sample()
        XCTAssertEqual(base.elapsed, 0, "ilk örnek taban çizgisi")
        XCTAssertTrue(base.groups.allSatisfy { $0.members.isEmpty }, "açık satır yokken üye süreç okunmaz")
        let mine = try XCTUnwrap(base.groups.first { $0.usage.footprint > 0 && $0.processCount > 0 && $0.key != ResourceKeys.system }?.key)
        _ = await live.sample(expanded: [mine])
        var x = 0.0; for i in 0..<2_000_000 { x += sin(Double(i)) }
        XCTAssertTrue(x != 0)
        let snap = await live.sample(expanded: [mine])
        XCTAssertGreaterThan(snap.elapsed, 0)
        XCTAssertFalse(snap.groups.isEmpty)
        XCTAssertEqual(snap.groups.filter { !$0.members.isEmpty }.map(\.key).filter { $0 != mine }, [], "yalnız açılan satırın üyeleri")
    }
}
