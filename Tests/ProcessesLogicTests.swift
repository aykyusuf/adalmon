import XCTest
@testable import Adalmon

/// Süreçler sayfası mantığı: GPU farkları, ısı yoğunluğu, kategori, satır/bölüm kurma, Başlangıç ayrıştırma, kayıtlı sorgular.
@MainActor
final class ProcessesLogicTests: XCTestCase {
    // MARK: GPU

    func testGPUDeltaTracker() {
        var t = GPUDeltaTracker()
        XCTAssertTrue(t.update([10: 1_000, 11: 500]).isEmpty, "ilk örnek taban çizgisidir")
        let d = t.update([10: 3_000, 11: 400, 12: 9_000])
        XCTAssertEqual(d[10], 2_000)
        XCTAssertNil(d[11], "geri giden sayaç (istemci yeniden açıldı) fark üretmez")
        XCTAssertNil(d[12], "yeni görülen süreç fark üretmez")
        XCTAssertEqual(t.update([10: 3_500, 12: 9_100])[12], 100)
    }

    func testEveryLiveRowGetsGPUPercentFromGroupUsage() {
        let live = ProcessLiveModel()
        let snap = LiveSnapshot(groups: [
            LiveGroup(key: "/Applications/A.app", usage: ResourceUsage(cpuNs: 0, gpuNs: 500_000_000, footprint: 50_000_000), processCount: 1, pids: [111], members: []),
            LiveGroup(key: "/Applications/B.app", usage: ResourceUsage(cpuNs: 0, gpuNs: 100_000_000, footprint: 60_000_000), processCount: 1, pids: [112], members: []),
        ], elapsed: 2)
        live.apply(snap, snapshot: nil, net: [:])
        let gpu = Dictionary(uniqueKeysWithValues: live.rows.map { ($0.key, $0.gpu) })
        XCTAssertEqual(gpu["/Applications/A.app"] ?? 0, 25, accuracy: 0.001)
        XCTAssertEqual(gpu["/Applications/B.app"] ?? 0, 5, accuracy: 0.001)
    }

    // MARK: Satırlar

    func testRatesNormalizeCPUToWholeMachine() {
        let r = LiveRow.Rates(usage: ResourceUsage(cpuNs: 4_000_000_000, writeBytes: 600, readBytes: 400), elapsed: 2, cores: 10)
        XCTAssertEqual(r.cpu, 20, accuracy: 0.001, "2 çekirdek-sn / (2 sn × 10 çekirdek) = %20")
        XCTAssertEqual(r.disk, 500, accuracy: 0.001, "okuma + yazma")
    }

    func testSectionsGroupSortAndSearch() {
        let live = ProcessLiveModel()
        let apps = [("/Applications/Zed.app", 1_000_000_000.0), ("/Applications/Alpha.app", 3_000_000_000.0)]
        var groups = apps.map { LiveGroup(key: $0.0, usage: ResourceUsage(cpuNs: UInt64($0.1), footprint: 80_000_000), processCount: 1, pids: [1], members: []) }
        groups.append(LiveGroup(key: ResourceKeys.system, usage: ResourceUsage(cpuNs: 500_000_000, footprint: 900_000_000), processCount: 40, pids: [2, 3], members: []))
        live.apply(LiveSnapshot(groups: groups, elapsed: 1, totalProcessCount: 42), snapshot: nil, net: ["/Applications/Zed.app": 6_000])
        XCTAssertEqual(live.totalProcessCount, 42)
        XCTAssertEqual(live.rows.first { $0.key == "/Applications/Zed.app" }?.network ?? 0, 100, accuracy: 0.001, "60 sn toplamı / 60")
        let sections = live.sections
        XCTAssertEqual(sections.last?.category, .system)
        let background = sections.first { $0.category == .background }?.rows.map(\.key)
        XCTAssertEqual(background, ["/Applications/Alpha.app", "/Applications/Zed.app"], "CPU azalan")
        live.sortColumn = .name
        live.sortAscending = true
        XCTAssertEqual(live.sections.first { $0.category == .background }?.rows.map(\.key), ["/Applications/Alpha.app", "/Applications/Zed.app"])
        live.query = "zed"
        XCTAssertEqual(live.sections.flatMap(\.rows).map(\.key), ["/Applications/Zed.app"])
        live.query = ""
        live.collapsed.insert(.background)
        XCTAssertTrue(live.sections.first { $0.category == .background }?.rows.isEmpty ?? false, "katlanmış bölüm satır göstermez")
    }

    func testCategoryClassification() {
        let regular: Set<String> = ["/Applications/Safari.app"]
        XCTAssertEqual(ProcessCategory.classify(key: "/Applications/Safari.app", regularAppPaths: regular), .app)
        XCTAssertEqual(ProcessCategory.classify(key: "/Applications/Raycast.app", regularAppPaths: regular), .background)
        XCTAssertEqual(ProcessCategory.classify(key: "/System/Library/CoreServices/Dock.app", regularAppPaths: regular), .system)
        XCTAssertEqual(ProcessCategory.classify(key: "/usr/libexec/trustd", regularAppPaths: regular), .system)
        XCTAssertEqual(ProcessCategory.classify(key: ResourceKeys.system, regularAppPaths: regular), .system)
    }

    func testSystemRowsCanNeverBeKilled() {
        let live = ProcessLiveModel()
        // getpid() kendi sürecimiz: normalde "sonlandırılabilir" değil; yine de sistem satırı için özellikle denetlenir.
        let system = LiveRow(id: "s", key: ResourceKeys.system, name: "Sistem", pid: nil, processCount: 2, pids: [Int32(getppid())],
                             category: .system, path: nil, cpu: 0, memory: 0, gpu: 0, disk: 0, network: 0, energy: 0)
        XCTAssertFalse(live.canKill(system))
        var loginwindow = system
        loginwindow.key = "/System/Library/CoreServices/loginwindow.app"
        loginwindow.pid = 77
        XCTAssertFalse(live.canKill(loginwindow), "sistem kategorisinin üye süreçleri de sonlandırılamaz")
        live.requestKill(system)
        XCTAssertNil(live.killRequest)
    }

    func testKillRules() {
        XCTAssertFalse(ProcessActions.isKillable(pid: 1), "launchd")
        XCTAssertFalse(ProcessActions.isKillable(pid: getpid()), "Adalmon kendini sonlandırmaz")
        XCTAssertFalse(ProcessActions.isKillable(pid: 0))
    }

    // MARK: Isı haritası

    func testHeatIntensity() {
        XCTAssertEqual(HeatTint.intensity(column: .cpu, value: 0), 0)
        XCTAssertGreaterThan(HeatTint.intensity(column: .cpu, value: 1), 0, "küçük ama sıfır olmayan değer belli olur")
        XCTAssertLessThan(HeatTint.intensity(column: .cpu, value: 5), HeatTint.intensity(column: .cpu, value: 30))
        XCTAssertEqual(HeatTint.intensity(column: .cpu, value: 500), 1, "üst sınır 1")
        XCTAssertEqual(HeatTint.intensity(column: .memory, value: 1e9, memoryTotal: 0), 0, "toplam bilinmiyorsa bellek boyanmaz")
        XCTAssertEqual(HeatTint.intensity(column: .memory, value: 16e9 * 0.2, memoryTotal: 16e9), 1)
        XCTAssertEqual(HeatTint.intensity(column: .name, value: 99), 0)
    }

    // MARK: Performans

    func testNiceCeilingAndUptime() {
        XCTAssertEqual(PerformanceChartView.niceCeiling(1_300_000), 2_000_000)
        XCTAssertEqual(PerformanceChartView.niceCeiling(4_100_000), 5_000_000)
        XCTAssertEqual(PerformanceChartView.niceCeiling(7_000_000), 10_000_000)
        XCTAssertEqual(PerformanceStatsBuilder.uptime(93_700), "1 g 2 sa 1 dk")
        XCTAssertEqual(PerformanceStatsBuilder.uptime(300), "5 dk")
    }

    func testStoredSeriesNormalizesCPUByBucketAndCores() {
        let totals = [ResourceTotalPoint(ts: 0, cpuNs: 60e9 * 5, gpuNs: 0, writeBytes: 60e6, readBytes: 0, footprint: 4e9)]
        let cpu = PerformanceSeriesBuilder.stored(metric: .cpu, totals: totals, window: .hour1, cores: 10, memoryTotal: 16e9)
        XCTAssertEqual(cpu.first?.points.first?.value ?? 0, 50, accuracy: 0.001, "5 çekirdek-dk / (1 dk × 10) = %50")
        let disk = PerformanceSeriesBuilder.stored(metric: .disk, totals: totals, window: .hour1, cores: 10, memoryTotal: 16e9)
        XCTAssertEqual(disk.last?.points.first?.value ?? 0, 1e6, accuracy: 1, "yazma baytı / 60 sn")
        let mem = PerformanceSeriesBuilder.stored(metric: .memory, totals: totals, window: .hour1, cores: 10, memoryTotal: 16e9)
        XCTAssertEqual(mem.first?.points.first?.value ?? 0, 25, accuracy: 0.001)
    }

    // MARK: Başlangıç

    func testStartupPlistParsing() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "startup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let on = dir.appending(path: "com.example.helper.plist")
        try PropertyListSerialization.data(fromPropertyList: ["Label": "com.example.helper", "ProgramArguments": ["/Applications/Example.app/Contents/MacOS/helper", "-x"], "RunAtLoad": true] as [String: Any],
                                           format: .xml, options: 0).write(to: on)
        let off = dir.appending(path: "com.example.off.plist")
        try PropertyListSerialization.data(fromPropertyList: ["Label": "com.example.off", "Program": "/usr/local/bin/off", "Disabled": true] as [String: Any],
                                           format: .xml, options: 0).write(to: off)
        let bad = dir.appending(path: "broken.plist")
        try Data("nope".utf8).write(to: bad)
        let a = try XCTUnwrap(StartupItemScanner.parse(url: on, scope: .user))
        XCTAssertEqual(a.name, "Example")
        XCTAssertEqual(a.status, .enabled)
        XCTAssertTrue(a.runsAtLoad)
        let b = try XCTUnwrap(StartupItemScanner.parse(url: off, scope: .allUsers))
        XCTAssertEqual(b.status, .disabled)
        XCTAssertEqual(b.name, "off")
        XCTAssertEqual(try XCTUnwrap(StartupItemScanner.parse(url: bad, scope: .user)).status, .unknown)
    }

    // MARK: Kayıtlı sorgular

    func testAppHistoryRowsAndTotalSeries() async {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ph-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UsageStore(path: dir.appending(path: "t.sqlite").path)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ts = Int(now.timeIntervalSince1970)
        func u(_ cpu: UInt64, _ wr: UInt64, _ fp: UInt64) -> ResourceUsage { ResourceUsage(cpuNs: cpu, gpuNs: 0, writeBytes: wr, readBytes: 5, energyNj: 0, footprint: fp) }
        await store.addResourceMinute(ts: ts - 600, rows: [KeyedUsage(key: "A", usage: u(1_000, 10, 100)), KeyedUsage(key: ResourceKeys.other, usage: u(500, 1, 50))], freeBytes: nil)
        await store.addResourceMinute(ts: ts - 540, rows: [KeyedUsage(key: "A", usage: u(2_000, 20, 300))], freeBytes: nil)
        await store.add(day: "2027-01-01", rows: [], hourly: [UsageStore.HourlyRow(hour: ts / 3_600 * 3_600 - 3_600, app: "A", domain: nil, mobile: false, bytesIn: 700, bytesOut: 300)])
        let rows = await store.appHistoryRows(window: .hours6, now: now)
        XCTAssertEqual(rows.map(\.app), ["A"], "__other__ tabloya girmez")
        XCTAssertEqual(rows.first?.cpuNs, 3_000)
        XCTAssertEqual(rows.first?.writeBytes, 30)
        XCTAssertEqual(rows.first?.memoryPeak, 300)
        XCTAssertEqual(rows.first?.networkBytes, 1_000, "ağ saatlik kullanım tablosundan")
        let totals = await store.resourceTotalSeries(window: .hour1, now: now)
        XCTAssertEqual(totals.reduce(0) { $0 + $1.cpuNs }, 3_500, "__other__ dahil sistem toplamı")
        XCTAssertEqual(totals.reduce(0) { $0 + $1.readBytes }, 15)
    }
}
