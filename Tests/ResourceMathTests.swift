import XCTest
@testable import Adalmon

final class ResourceMathTests: XCTestCase {
    private func counters(cpu: UInt64 = 0, wr: UInt64 = 0, gpu: UInt64 = 0, en: UInt64 = 0, fp: UInt64 = 0, started: UInt64 = 10) -> CoalitionCounters {
        CoalitionCounters(tasksStarted: started, tasksExited: 0, cpuTicks: cpu, bytesRead: 0, bytesWritten: wr, gpuNs: gpu, energyNj: en, footprint: fp)
    }

    func testTimebaseConversionAppleSilicon() {
        let tb = MachTimebase(numer: 125, denom: 3)
        XCTAssertEqual(tb.nanos(3), 125)
        XCTAssertEqual(tb.nanos(24_000_000), 1_000_000_000) // 24 M tick = 1 sn
        XCTAssertEqual(tb.nanos(0), 0)
        XCTAssertEqual(tb.nanos(4), 166, "4*125/3 = 166,67 → tam sayı kesilir")
        // Çok büyük sayaçta çarpma taşmaz (tick*125 doğrudan taşardı).
        let big: UInt64 = 300_000_000_000_000_000
        XCTAssertEqual(tb.nanos(big), 12_500_000_000_000_000_000)
        XCTAssertEqual(MachTimebase(numer: 1, denom: 1).nanos(42), 42)
    }

    func testFirstSweepIsBaselineThenDeltas() {
        var t = CoalitionDeltaTracker()
        let tb = MachTimebase(numer: 1, denom: 1)
        let first = t.update([1: counters(cpu: 1_000, wr: 500, fp: 7)], timebase: tb)
        XCTAssertEqual(first[1]?.cpuNs, 0)
        XCTAssertEqual(first[1]?.writeBytes, 0)
        XCTAssertEqual(first[1]?.footprint, 7, "footprint anlık değerdir, delta değil")
        let second = t.update([1: counters(cpu: 1_600, wr: 800, gpu: 40, en: 9, fp: 9)], timebase: tb)
        XCTAssertEqual(second[1], ResourceUsage(cpuNs: 600, gpuNs: 40, writeBytes: 300, readBytes: 0, energyNj: 9, footprint: 9))
    }

    func testNewCoalitionAfterBaselineCountsFullCumulative() {
        var t = CoalitionDeltaTracker()
        let tb = MachTimebase(numer: 1, denom: 1)
        _ = t.update([1: counters(cpu: 10)], timebase: tb)
        let u = t.update([1: counters(cpu: 10), 2: counters(cpu: 500, wr: 77)], timebase: tb)
        XCTAssertEqual(u[2]?.cpuNs, 500, "yeni coalition aralık içinde doğdu")
        XCTAssertEqual(u[2]?.writeBytes, 77)
        XCTAssertEqual(u[1]?.cpuNs, 0)
    }

    func testCounterResetAndCoalitionReuseYieldZeroNotNegative() {
        var t = CoalitionDeltaTracker()
        let tb = MachTimebase(numer: 1, denom: 1)
        _ = t.update([1: counters(cpu: 1_000, wr: 1_000, started: 50)], timebase: tb)
        // tasks_started geriledi: numara yeniden kullanıldı → o tur 0
        let reused = t.update([1: counters(cpu: 900, wr: 5_000, started: 3)], timebase: tb)
        XCTAssertEqual(reused[1]?.cpuNs, 0)
        XCTAssertEqual(reused[1]?.writeBytes, 0)
        // ertesi tur yeni tabandan normal fark
        let next = t.update([1: counters(cpu: 1_000, wr: 5_100, started: 3)], timebase: tb)
        XCTAssertEqual(next[1]?.cpuNs, 100)
        XCTAssertEqual(next[1]?.writeBytes, 100)
        // tek sayaç geri giderse (yalnız yazma) yalnız o 0
        let partial = t.update([1: counters(cpu: 1_050, wr: 10, started: 3)], timebase: tb)
        XCTAssertEqual(partial[1]?.cpuNs, 50)
        XCTAssertEqual(partial[1]?.writeBytes, 0)
    }

    func testVanishedCoalitionIsForgottenAndNotReplayed() {
        var t = CoalitionDeltaTracker()
        let tb = MachTimebase(numer: 1, denom: 1)
        _ = t.update([1: counters(cpu: 10), 2: counters(cpu: 1_000_000)], timebase: tb)
        for _ in 0..<12 { _ = t.update([1: counters(cpu: 10)], timebase: tb) }
        // Unutulan 2 geri gelirse yeni sayılır (tam birikimli): bilinçli sınır, yalnız ≥5 süpürme kayıpta.
        let back = t.update([1: counters(cpu: 10), 2: counters(cpu: 1_000_100)], timebase: tb)
        XCTAssertEqual(back[2]?.cpuNs, 1_000_100)
        // Kısa süreli kayıpta (1 süpürme) tabanı korur.
        _ = t.update([1: counters(cpu: 10)], timebase: tb)
        let short = t.update([1: counters(cpu: 10), 2: counters(cpu: 1_000_200)], timebase: tb)
        XCTAssertEqual(short[2]?.cpuNs, 100)
    }

    func testProcessTrackerTreatsReusedPidAsNewProcess() {
        var t = ProcessDeltaTracker()
        let tb = MachTimebase(numer: 1, denom: 1)
        let a = ProcessKey(pid: 5, start: 100)
        _ = t.update([a: ProcessCounters(cpuTicks: 1_000, bytesWritten: 9_000)], timebase: tb)
        // aynı pid, yeni başlangıç zamanı → yeni süreç: ilk örnek delta 0 (eski sayaçla karşılaştırılmaz)
        let b = ProcessKey(pid: 5, start: 200)
        let u = t.update([b: ProcessCounters(cpuTicks: 10, bytesWritten: 3)], timebase: tb)
        XCTAssertEqual(u[b]?.cpuNs, 0)
        XCTAssertEqual(u[b]?.writeBytes, 0)
        let v = t.update([b: ProcessCounters(cpuTicks: 40, bytesWritten: 13)], timebase: tb)
        XCTAssertEqual(v[b]?.cpuNs, 30)
        XCTAssertEqual(v[b]?.writeBytes, 10)
    }

    func testTopNUnionKeepsTopPerMetricAndFoldsRestIntoOther() {
        var items: [KeyedUsage] = []
        for i in 0..<40 {
            items.append(KeyedUsage(key: "app\(i)", usage: ResourceUsage(cpuNs: UInt64(i + 1) * 10, footprint: 1)))
        }
        items.append(KeyedUsage(key: "writer", usage: ResourceUsage(cpuNs: 1, writeBytes: 9_000_000, footprint: 1)))
        let out = TopNUnion.select(items, perMetric: 3)
        let keys = Set(out.map(\.key))
        XCTAssertTrue(keys.isSuperset(of: ["app39", "app38", "app37", "writer"]))
        XCTAssertTrue(keys.contains(ResourceKeys.other))
        XCTAssertEqual(out.reduce(0) { $0 + $1.usage.cpuNs }, items.reduce(0) { $0 + $1.usage.cpuNs }, "toplamlar korunur")
        XCTAssertEqual(out.reduce(0) { $0 + $1.usage.footprint }, items.reduce(0) { $0 + $1.usage.footprint })
        XCTAssertLessThan(out.count, items.count)
    }

    func testTopNUnionMergesSameKeyAndSkipsZeroMetrics() {
        let a = KeyedUsage(key: "X", usage: ResourceUsage(cpuNs: 5))
        let b = KeyedUsage(key: "X", usage: ResourceUsage(cpuNs: 7, footprint: 100))
        let z = KeyedUsage(key: "Z", usage: .zero)
        let out = TopNUnion.select([a, b, z], perMetric: 15)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.usage.cpuNs, 12)
        XCTAssertNil(out.first { $0.key == ResourceKeys.other }, "boş kalan yok → other satırı yok")
        XCTAssertNil(out.first { $0.key == "Z" })
    }

    func testFolderGrowthCollapseDropsParentDominatedByChild() {
        let parent = FolderGrowth(path: "/h/Dev", depth: 1, currentBytes: 10, growthBytes: 100)
        let child = FolderGrowth(path: "/h/Dev/DerivedData", depth: 2, currentBytes: 9, growthBytes: 90)
        let other = FolderGrowth(path: "/h/Caches", depth: 1, currentBytes: 5, growthBytes: 30)
        XCTAssertEqual(Set(FolderGrowthCollapse.collapse([parent, child, other]).map(\.path)), ["/h/Dev/DerivedData", "/h/Caches"])
        let small = FolderGrowth(path: "/h/Dev/Small", depth: 2, currentBytes: 1, growthBytes: 20)
        XCTAssertEqual(Set(FolderGrowthCollapse.collapse([parent, small]).map(\.path)), ["/h/Dev", "/h/Dev/Small"])
        let sibling = FolderGrowth(path: "/h/Dev2", depth: 1, currentBytes: 1, growthBytes: 99)
        XCTAssertEqual(Set(FolderGrowthCollapse.collapse([parent, sibling]).map(\.path)), ["/h/Dev", "/h/Dev2"])
    }

    func testScanPolicy() {
        XCTAssertNotNil(ScanPolicy.skipReason(lowPowerMode: true, onBattery: false, batteryPercent: 90))
        XCTAssertNotNil(ScanPolicy.skipReason(lowPowerMode: false, onBattery: true, batteryPercent: 19))
        XCTAssertNil(ScanPolicy.skipReason(lowPowerMode: false, onBattery: true, batteryPercent: 20))
        XCTAssertNil(ScanPolicy.skipReason(lowPowerMode: false, onBattery: false, batteryPercent: 5))
        XCTAssertTrue(ScanPolicy.canSkipAsIdle(bytesWrittenSinceScan: 1_000, secondsSinceScan: 3_600))
        XCTAssertFalse(ScanPolicy.canSkipAsIdle(bytesWrittenSinceScan: 500_000_000, secondsSinceScan: 3_600))
        XCTAssertFalse(ScanPolicy.canSkipAsIdle(bytesWrittenSinceScan: 0, secondsSinceScan: 8 * 3_600))
    }

    func testGPUClientCreatorParsing() {
        XCTAssertEqual(GPUClientUsage.parsePID("pid 601, WindowServer"), 601)
        XCTAssertNil(GPUClientUsage.parsePID("kernel_task"))
    }
}
