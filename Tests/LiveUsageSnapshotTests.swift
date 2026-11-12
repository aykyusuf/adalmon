import XCTest
@testable import Adalmon

/// Canlı kullanım listesinin kalıcılığı: kaydet → yükle, eski veri, bozuk dosya, saat geri gitmesi, uygulama sınırı.
/// Yalnızca geçici dizin; gerçek Application Support dosyasına dokunulmaz.
final class LiveUsageSnapshotTests: XCTestCase {
    private let chrome = "/Applications/Google Chrome.app"
    private let slack = "/Applications/Slack.app"
    private let m0 = 29_000_000
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "adalmon-live-snapshot-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private var fileURL: URL { dir.appending(path: "live-usage.snapshot") }

    private func sampleHistory() -> LiveUsageHistory {
        var h = LiveUsageHistory()
        for k in 0..<60 {
            h.record(app: chrome, bytesIn: UInt64(1_000 + k), bytesOut: UInt64(k), mobile: k % 2 == 0, minute: m0 - k)
            if k % 3 == 0 { h.record(app: slack, bytesIn: 77, bytesOut: 5, mobile: false, minute: m0 - k) }
        }
        h.record(app: "/Users/ü/Ünïcode ✓.app", bytesIn: UInt64.max / 4, bytesOut: 1, mobile: true, minute: m0)
        return h
    }

    private func rowsEqual(_ a: LiveUsageHistory, _ b: LiveUsageHistory, now: Int, file: StaticString = #filePath, line: UInt = #line) {
        for range in LiveRange.allCases where range != .now && range != .sec60 {
            for iface in LiveInterface.allCases {
                // `rate` saniye halkasından gelir (kalıcı değil); dakika toplamları birebir aynı olmalı.
                func key(_ h: LiveUsageHistory) -> [String] {
                    h.rows(range: range, interface: iface, nowMinute: now).map { "\($0.app)|\($0.down)|\($0.up)" }
                }
                XCTAssertEqual(key(a), key(b), "\(range.title) \(iface)", file: file, line: line)
            }
        }
    }

    // MARK: Kaydet → yükle

    func testCodecRoundTripKeepsEveryRangeAndInterface() throws {
        let h = sampleHistory()
        let snap = h.snapshot(nowMinute: m0, savedAt: 1_740_000_000)
        let decoded = try XCTUnwrap(LiveUsageSnapshot.decode(snap.encoded()))
        XCTAssertEqual(decoded, snap)
        var restored = LiveUsageHistory()
        restored.restore(decoded, nowMinute: m0)
        rowsEqual(h, restored, now: m0)
        XCTAssertEqual(restored.rows(range: .hour1, interface: .mobile, nowMinute: m0).first?.app, "/Users/ü/Ünïcode ✓.app", "uygulama anahtarı birebir")
    }

    func testStoreSaveThenLoadAcrossInstances() async throws {
        let h = sampleHistory()
        let store = LiveUsageSnapshotStore(url: fileURL)
        store.save(history: h, nowMinute: m0, savedAt: 1)
        store.waitUntilIdle()
        let loaded = await LiveUsageSnapshotStore(url: fileURL).load()
        var restored = LiveUsageHistory()
        restored.restore(try XCTUnwrap(loaded), nowMinute: m0)
        rowsEqual(h, restored, now: m0)
    }

    func testRestoreAddsToAlreadyMeasuredMinutes() {
        var saved = LiveUsageHistory()
        saved.record(app: chrome, bytesIn: 100, bytesOut: 0, mobile: false, minute: m0)
        var fresh = LiveUsageHistory()
        fresh.record(app: chrome, bytesIn: 40, bytesOut: 0, mobile: false, minute: m0)
        fresh.restore(saved.snapshot(nowMinute: m0, savedAt: 0), nowMinute: m0)
        XCTAssertEqual(fresh.totals(range: .min5, nowMinute: m0)[chrome]?.down, 140)
    }

    func testMissingFileLoadsNil() async {
        let loaded = await LiveUsageSnapshotStore(url: fileURL).load()
        XCTAssertNil(loaded)
    }

    func testRealisticAndWorstCaseSizes() {
        var h = LiveUsageHistory()
        for k in 0..<60 { for a in 0..<15 { h.record(app: "/Applications/App\(a + k % 5).app", bytesIn: UInt64(50_000 * (a + 1)), bytesOut: 4_000, mobile: a % 4 == 0, minute: m0 - k) } }
        let typical = h.snapshot(nowMinute: m0, savedAt: 0).encoded().count
        var big = LiveUsageHistory()
        for k in 0..<60 { for a in 0..<200 { big.record(app: "/Applications/Some Longer Application Name \(a).app", bytesIn: 3_000_000, bytesOut: 90_000, mobile: true, minute: m0 - k) } }
        let worst = big.snapshot(nowMinute: m0, savedAt: 0).encoded().count
        print("LIVE-SNAPSHOT-SIZE typical(15 app/dk, ~20 uygulama)=\(typical) B worst(200x60)=\(worst) B")
        XCTAssertLessThan(typical, 64 * 1024)
        XCTAssertLessThan(worst, 256 * 1024)
    }

    // MARK: Eski veri, saat

    func testMinutesOlderThanAnHourAreDroppedOnSaveAndRestore() {
        var h = LiveUsageHistory()
        h.record(app: chrome, bytesIn: 1, bytesOut: 0, mobile: false, minute: m0)          // şimdi
        h.record(app: chrome, bytesIn: 10, bytesOut: 0, mobile: false, minute: m0 - 59)    // sınırda, kalır
        h.record(app: chrome, bytesIn: 100, bytesOut: 0, mobile: false, minute: m0 - 60)   // tam 1 saat: düşer
        h.record(app: chrome, bytesIn: 1_000, bytesOut: 0, mobile: false, minute: m0 - 500)
        let snap = h.snapshot(nowMinute: m0, savedAt: 0)
        XCTAssertEqual(Set(snap.minutes.keys), [m0, m0 - 59])

        // Uygulama 30 dk kapalı kaldı: yeni "şimdi" = m0 + 30 → yalnızca m0 (30 dk önce) kalır, m0 - 59 düşer.
        var restored = LiveUsageHistory()
        restored.restore(snap, nowMinute: m0 + 30)
        XCTAssertEqual(restored.allMinutes.keys.sorted(), [m0])
        // 2 saat kapalı: hiçbir şey kalmaz.
        var later = LiveUsageHistory()
        later.restore(snap, nowMinute: m0 + 120)
        XCTAssertTrue(later.allMinutes.isEmpty)
    }

    func testClockMovedBackwardDropsFutureMinutesKeepsPast() {
        let h = sampleHistory()
        let snap = h.snapshot(nowMinute: m0, savedAt: 0)
        var restored = LiveUsageHistory()
        restored.restore(snap, nowMinute: m0 - 30) // saat 30 dk geri
        XCTAssertTrue(restored.allMinutes.keys.allSatisfy { $0 <= m0 - 29 })
        XCTAssertEqual(restored.allMinutes.keys.min(), m0 - 59)
        // Saat bir gün geri: hepsi gelecekte → boş.
        var way = LiveUsageHistory()
        way.restore(snap, nowMinute: m0 - 1_440)
        XCTAssertTrue(way.allMinutes.isEmpty)
        // Kaydederken de gelecek kovalar yazılmaz.
        XCTAssertTrue(h.snapshot(nowMinute: m0 - 1_440, savedAt: 0).isEmpty)
    }

    // MARK: Bozuk dosya

    func testCorruptFilesAreIgnoredAndReplacedByAValidFile() async throws {
        let good = sampleHistory().snapshot(nowMinute: m0, savedAt: 5).encoded()
        var flipped = good; flipped[flipped.count / 2] ^= 0xFF
        let cases: [(String, Data)] = [
            ("çöp", Data("not a snapshot at all".utf8)),
            ("boş", Data()),
            ("kesik", good.prefix(good.count - 7)),
            ("bit hatası", flipped),
            ("fazladan bayt", good + Data([0])),
            ("yanlış sürüm", Data([0x41, 0x4C, 0x55, 0x53, 9]) + good.dropFirst(5)),
        ]
        for (name, data) in cases {
            try data.write(to: fileURL)
            let store = LiveUsageSnapshotStore(url: fileURL)
            let loaded = await store.load()
            XCTAssertNil(loaded, name)
            // Dosya geçerli ve boş bir anlık görüntüyle değiştirildi.
            let after = LiveUsageSnapshot.decode(try Data(contentsOf: fileURL))
            XCTAssertEqual(after, LiveUsageSnapshot(), name)
        }
    }

    func testRandomGarbageNeverCrashesDecoder() {
        var rng = SystemRandomNumberGenerator()
        let good = [UInt8](sampleHistory().snapshot(nowMinute: m0, savedAt: 5).encoded())
        for _ in 0..<500 {
            var bytes = good
            for _ in 0..<3 { bytes[Int.random(in: 0..<bytes.count, using: &rng)] = UInt8.random(in: 0...255, using: &rng) }
            _ = LiveUsageSnapshot.decode(Data(bytes)) // çökmemesi yeter (sağlama toplamı çoğunu eler)
            _ = LiveUsageSnapshot.decode(Data((0..<Int.random(in: 0..<64, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }))
        }
    }

    // MARK: Boyut sınırı

    func testMoreThanTwoHundredAppsKeepsTheBusiest() {
        var h = LiveUsageHistory()
        for a in 0..<300 { h.record(app: "/Applications/A\(a).app", bytesIn: UInt64(1_000 + a), bytesOut: 0, mobile: false, minute: m0) }
        let snap = h.snapshot(nowMinute: m0, savedAt: 0)
        let apps = Set(snap.minutes.values.flatMap { $0.keys })
        XCTAssertEqual(apps.count, LiveUsageHistory.maxPersistedApps)
        XCTAssertTrue(apps.contains("/Applications/A299.app"))
        XCTAssertFalse(apps.contains("/Applications/A0.app"))
        XCTAssertFalse(apps.contains("/Applications/A99.app"), "en küçük 100 düşer")
        XCTAssertTrue(apps.contains("/Applications/A100.app"))
    }

    // MARK: Motor bağlantısı

    @MainActor
    private func bucket(_ app: String, minute: Int, bytes: UInt64 = 1_000, expensive: Bool = false) -> UsageBucket {
        UsageBucket(app: app, signingID: "", host: "x.test", kind: .direct, expensive: expensive, minute: minute, bytesIn: bytes, bytesOut: 10)
    }

    @MainActor
    func testEngineRestoresAfterRestartAndPeriodicWriteIsThrottledAndDirtyOnly() async throws {
        let store = LiveUsageSnapshotStore(url: fileURL)
        let t0 = Date(timeIntervalSince1970: Double(m0 * 60 + 10))
        let a = UsageEngine(store: UsageStore(), liveStore: store)
        await a.restoreLive(now: t0)
        a.ingest([bucket(chrome, minute: m0, expensive: true)], now: t0)
        await a.flush(now: t0) // sayaç başlar

        await a.flush(now: t0.addingTimeInterval(10))
        store.waitUntilIdle()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "5 dk dolmadan yazılmaz")

        await a.flush(now: t0.addingTimeInterval(UsageEngine.liveSaveInterval + 1))
        store.waitUntilIdle()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "5 dk sonra ve veri değişmişse yazılır")

        // Veri değişmediyse tekrar yazılmaz: dosyayı işaretle, sonraki flush onu ezmemeli.
        let marker = Data("marker".utf8)
        try marker.write(to: fileURL)
        await a.flush(now: t0.addingTimeInterval(2 * UsageEngine.liveSaveInterval + 5))
        store.waitUntilIdle()
        XCTAssertEqual(try Data(contentsOf: fileURL), marker, "değişiklik yoksa yazma yok")

        // Yeniden başlatma: yeni motor dosyadan okur; 10 dk sonra, 1 sa penceresinde.
        a.ingest([bucket(slack, minute: m0 + 1)], now: t0.addingTimeInterval(60))
        a.saveLiveNow(now: t0.addingTimeInterval(70)) // çıkış yolu (senkron)
        let t1 = t0.addingTimeInterval(600)
        let b = UsageEngine(store: UsageStore(), liveStore: LiveUsageSnapshotStore(url: fileURL))
        await b.restoreLive(now: t1)
        let rows = b.liveRows(range: .hour1, interface: .all, now: t1)
        XCTAssertEqual(Set(rows.map(\.app)), [chrome, slack])
        XCTAssertEqual(rows.first { $0.app == chrome }?.bytes, 1_010)
        XCTAssertEqual(b.liveRows(range: .hour1, interface: .mobile, now: t1).map(\.app), [chrome], "mobil payı korunur")
    }

    @MainActor
    func testEngineNeverWritesBeforeRestoreCompletes() {
        let store = LiveUsageSnapshotStore(url: fileURL)
        let e = UsageEngine(store: UsageStore(), liveStore: store)
        let t = Date(timeIntervalSince1970: Double(m0 * 60))
        e.ingest([bucket(chrome, minute: m0)], now: t)
        e.saveLiveNow(now: t)
        store.waitUntilIdle()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "açılış yedeği okunmadan eski dosya ezilmez")
    }

    @MainActor
    func testEngineWithoutStoreIsUnchanged() async {
        let e = UsageEngine(store: UsageStore())
        let t = Date.now
        e.ingest([bucket(chrome, minute: Int(t.timeIntervalSince1970) / 60)], now: t)
        await e.restoreLive(now: t)
        e.saveLiveNow(now: t)
        XCTAssertEqual(e.liveRows(range: .min5, interface: .all, now: t).count, 1)
    }
}
