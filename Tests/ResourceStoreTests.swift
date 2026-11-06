import XCTest
@testable import Adalmon

final class ResourceStoreTests: XCTestCase {
    private var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "res-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }
    private func makeStore() -> UsageStore { UsageStore(path: dir.appending(path: "t.sqlite").path) }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var nowTs: Int { Int(now.timeIntervalSince1970) }
    private func u(cpu: UInt64 = 0, gpu: UInt64 = 0, wr: UInt64 = 0, en: UInt64 = 0, fp: UInt64 = 0) -> ResourceUsage {
        ResourceUsage(cpuNs: cpu, gpuNs: gpu, writeBytes: wr, readBytes: 0, energyNj: en, footprint: fp)
    }

    func testTopConsumersByMetricAndWindow() async {
        let s = makeStore()
        // 90 dk önce: A büyük CPU; 10 dk önce: B küçük CPU, büyük yazma
        await s.addResourceMinute(ts: nowTs - 5_400, rows: [KeyedUsage(key: "A", usage: u(cpu: 9_000, fp: 100))], freeBytes: nil)
        await s.addResourceMinute(ts: nowTs - 600, rows: [KeyedUsage(key: "B", usage: u(cpu: 100, wr: 5_000, fp: 400)),
                                                          KeyedUsage(key: "A", usage: u(cpu: 50, fp: 300)),
                                                          KeyedUsage(key: ResourceKeys.other, usage: u(cpu: 99_999))], freeBytes: nil)
        let cpu6h = await s.topConsumers(metric: .cpu, window: .hours6, now: now)
        XCTAssertEqual(cpu6h.map(\.app), ["A", "B"], "__other__ sıralamaya girmez")
        XCTAssertEqual(cpu6h.first?.value, 9_050)
        let cpu1h = await s.topConsumers(metric: .cpu, window: .hour1, now: now)
        XCTAssertEqual(cpu1h.map(\.app), ["B", "A"], "90 dk önceki kayıt 1 saatlik pencereye girmez")
        let wr = await s.topConsumers(metric: .diskWrite, window: .hour1, now: now)
        XCTAssertEqual(wr.map(\.app), ["B"], "değeri 0 olan uygulama listelenmez")
        let peak = await s.topConsumers(metric: .memoryPeak, window: .hours6, now: now)
        XCTAssertEqual(peak.first?.app, "B"); XCTAssertEqual(peak.first?.value, 400)
        let avg = await s.topConsumers(metric: .memoryAvg, window: .hours6, now: now)
        XCTAssertEqual(avg.first { $0.app == "A" }?.value, 200, "A: (100+300)/2")
    }

    func testRolloverMergesOldMinutesIntoHoursAndPrunesAfter7Days() async {
        let s = makeStore()
        let hourStart = (nowTs - 30 * 3_600) / 3_600 * 3_600
        // 30 saat önce aynı saatte 3 dakika
        for m in 0..<3 {
            await s.addResourceMinute(ts: hourStart + m * 60, rows: [KeyedUsage(key: "A", usage: u(cpu: 10, wr: 5, fp: UInt64(100 * (m + 1))))], freeBytes: 1_000)
        }
        // taze dakika (kalmalı)
        await s.addResourceMinute(ts: nowTs - 60, rows: [KeyedUsage(key: "A", usage: u(cpu: 7, fp: 50))], freeBytes: 900)
        // 8 gün önce (silinmeli)
        await s.addResourceMinute(ts: nowTs - 8 * 86_400, rows: [KeyedUsage(key: "OLD", usage: u(cpu: 1))], freeBytes: 5)
        await s.resourceMaintenance(now: now)
        await s.resourceMaintenance(now: now) // idempotent
        let c = await s.resourceRowCounts()
        XCTAssertEqual(c.minute, 1, "yalnız taze dakika kalır")
        XCTAssertEqual(c.hour, 1, "3 dakika tek saatlik satırda toplandı; 8 gün öncesi silindi")
        XCTAssertEqual(c.apps, 1, "kullanılmayan uygulama anahtarı temizlendi")
        let cpu7d = await s.topConsumers(metric: .cpu, window: .days7, now: now)
        XCTAssertEqual(cpu7d.first?.value, 37, "30 (saatlik) + 7 (dakikalık)")
        let wr = await s.topConsumers(metric: .diskWrite, window: .days7, now: now)
        XCTAssertEqual(wr.first?.value, 15)
        let peak = await s.topConsumers(metric: .memoryPeak, window: .days7, now: now)
        XCTAssertEqual(peak.first?.value, 300)
        let avg = await s.topConsumers(metric: .memoryAvg, window: .days7, now: now)
        XCTAssertEqual(avg.first?.value, (100 + 200 + 300 + 50) / 4.0)
        // 24 saatlik pencere saatlik satırı görmez
        let cpu24 = await s.topConsumers(metric: .cpu, window: .hours24, now: now)
        XCTAssertEqual(cpu24.first?.value, 7)
        let free = await s.diskFreeSeries(window: .days7, now: now)
        XCTAssertEqual(free.count >= 1, true)
        XCTAssertFalse(free.contains { $0.freeBytes == 5 })
    }

    func testRolloverMergesIntoExistingHourRow() async {
        let s = makeStore()
        let hourStart = (nowTs - 30 * 3_600) / 3_600 * 3_600
        await s.addResourceMinute(ts: hourStart, rows: [KeyedUsage(key: "A", usage: u(cpu: 10, fp: 100))], freeBytes: nil)
        await s.resourceMaintenance(now: now)
        await s.addResourceMinute(ts: hourStart + 60, rows: [KeyedUsage(key: "A", usage: u(cpu: 5, fp: 300))], freeBytes: nil)
        await s.resourceMaintenance(now: now)
        let c = await s.resourceRowCounts()
        XCTAssertEqual(c.hour, 1)
        let peak = await s.topConsumers(metric: .memoryPeak, window: .days7, now: now)
        XCTAssertEqual(peak.first?.value, 300)
        let cpu = await s.topConsumers(metric: .cpu, window: .days7, now: now)
        XCTAssertEqual(cpu.first?.value, 15)
    }

    func testSeriesFillsEmptyBuckets() async {
        let s = makeStore()
        await s.addResourceMinute(ts: nowTs - 120, rows: [KeyedUsage(key: "A", usage: u(cpu: 10))], freeBytes: nil)
        let series = await s.resourceSeries(app: "A", metric: .cpu, window: .hour1, now: now)
        XCTAssertGreaterThanOrEqual(series.count, 60)
        XCTAssertEqual(series.map(\.value).reduce(0, +), 10)
        XCTAssertEqual(series.filter { $0.value > 0 }.count, 1)
        let none = await s.resourceSeries(app: "nope", metric: .cpu, window: .hour1, now: now)
        XCTAssertEqual(none.map(\.value).reduce(0, +), 0)
    }

    func testFolderGrowthComparesLatestToWindowBase() async {
        let s = makeStore()
        let gb: UInt64 = 1_000_000_000
        await s.addFolderSnapshot(ts: nowTs - 7 * 3_600, entries: [
            FolderSnapshotEntry(path: "/h/Caches", depth: 0, bytes: 10 * gb), FolderSnapshotEntry(path: "/h/Caches/x", depth: 1, bytes: 2 * gb),
        ])
        await s.addFolderSnapshot(ts: nowTs - 3_600, entries: [
            FolderSnapshotEntry(path: "/h/Caches", depth: 0, bytes: 13 * gb), FolderSnapshotEntry(path: "/h/Caches/x", depth: 1, bytes: 5 * gb),
            FolderSnapshotEntry(path: "/h/new", depth: 1, bytes: gb),
        ])
        let day = await s.folderGrowth(window: .hours24, now: now)
        XCTAssertTrue(day.hasComparison)
        XCTAssertEqual(day.baseTs, nowTs - 7 * 3_600, "pencere başından önce kayıt yok → en eski")
        XCTAssertEqual(day.items.first?.path, "/h/Caches/x", "üst klasör (+3 GB) çocuk (+3 GB) tarafından elenir")
        XCTAssertEqual(day.items.first?.growthBytes, Int64(3 * gb))
        XCTAssertTrue(day.items.contains { $0.path == "/h/new" })
        XCTAssertFalse(day.items.contains { $0.path == "/h/Caches" })
        let h1 = await s.folderGrowth(window: .hour1, now: now)
        XCTAssertEqual(h1.baseTs, nowTs - 7 * 3_600, "1 saatlik pencerede başlangıçtan önceki son tarama bu")
        let last = await s.lastFolderScan()
        XCTAssertEqual(last, nowTs - 3_600)
    }

    func testFolderAbsentFromBaseIsBoundedByRecordingThreshold() async {
        let s = makeStore()
        let mb: UInt64 = 1_048_576
        await s.addFolderSnapshot(ts: nowTs - 7_200, entries: [FolderSnapshotEntry(path: "/h", depth: 0, bytes: 900 * mb)])
        await s.addFolderSnapshot(ts: nowTs - 60, entries: [
            FolderSnapshotEntry(path: "/h", depth: 0, bytes: 905 * mb),
            FolderSnapshotEntry(path: "/h/borderline", depth: 1, bytes: 12 * mb),  // eşiği az geçti: tabanda <10 MB'dı
            FolderSnapshotEntry(path: "/h/huge", depth: 1, bytes: 4_000 * mb),
        ])
        let r = await s.folderGrowth(window: .hours6, now: now)
        let byPath = Dictionary(uniqueKeysWithValues: r.items.map { ($0.path, $0.growthBytes) })
        XCTAssertEqual(byPath["/h/borderline"], Int64(2 * mb), "12 MB - 10 MB eşik; 12 MB'lık büyüme iddia edilmez")
        XCTAssertEqual(byPath["/h/huge"], Int64(3_990 * mb))
        XCTAssertEqual(byPath["/h"], nil, "kök (+5 MB) altındaki çocuklardan biri tarafından elendi ya da küçük")
    }

    func testCarryForwardOfSkippedRoots() async {
        let s = makeStore()
        await s.addFolderSnapshot(ts: nowTs - 7_200, entries: [
            FolderSnapshotEntry(path: "/h/.gradle", depth: 0, bytes: 100), FolderSnapshotEntry(path: "/h/.gradle/caches", depth: 1, bytes: 90),
            FolderSnapshotEntry(path: "/h/.gradleX", depth: 0, bytes: 7), FolderSnapshotEntry(path: "/h/Caches", depth: 0, bytes: 5)])
        let carried = await s.latestFolderEntries(underRoots: ["/h/.gradle"])
        XCTAssertEqual(Set(carried.map(\.path)), ["/h/.gradle", "/h/.gradle/caches"], "önek eşleşmesi klasör sınırında")
        let none = await s.latestFolderEntries(underRoots: [])
        XCTAssertTrue(none.isEmpty)
    }

    func testFolderGrowthSingleSnapshotHasNoComparison() async {
        let s = makeStore()
        await s.addFolderSnapshot(ts: nowTs, entries: [FolderSnapshotEntry(path: "/a", depth: 0, bytes: 5)])
        let r = await s.folderGrowth(window: .hour1, now: now)
        XCTAssertFalse(r.hasComparison)
        XCTAssertTrue(r.items.isEmpty)
        let empty = await UsageStore(path: dir.appending(path: "empty.sqlite").path).folderGrowth(window: .hour1, now: now)
        XCTAssertNil(empty.latestTs)
    }

    func testRecentTop() async {
        let s = makeStore()
        await s.addResourceMinute(ts: nowTs - 30, rows: [KeyedUsage(key: "A", usage: u(cpu: 5, fp: 9)), KeyedUsage(key: "B", usage: u(cpu: 50, fp: 1))], freeBytes: nil)
        await s.addResourceMinute(ts: nowTs - 3_600, rows: [KeyedUsage(key: "C", usage: u(cpu: 500))], freeBytes: nil)
        let top = await s.recentTop(metric: .cpu, minutes: 5, now: now)
        XCTAssertEqual(top.map(\.app), ["B", "A"])
        let mem = await s.recentTop(metric: .memoryPeak, minutes: 5, now: now)
        XCTAssertEqual(mem.first?.app, "A")
    }
}
