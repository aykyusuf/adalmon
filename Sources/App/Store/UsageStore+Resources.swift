import Foundation
import SQLite3

/// Süreç/kaynak geçmişi (Faz 3): dakikalık satırlar (ilk 15 birleşimi + `__other__`), 24 saatten eskiler saatlik, 7 gün saklama.
/// Disk: boş alan zaman serisi ve saatlik klasör boyutu anlık görüntüleri.
extension UsageStore {
    /// Dakikalık satırlar bu süreden sonra saatliğe toplanır.
    static let minuteRetentionSeconds = 86_400
    /// Her şey (saatlik, disk) bu süreden sonra silinir.
    static let resourceRetentionSeconds = 7 * 86_400
    /// Klasör taramasında kaydedilen alt klasör alt sınırı (bkz. `FolderScanner.defaultMinRecordedBytes`).
    static let recordingThreshold: UInt64 = FolderScanner.defaultMinRecordedBytes

    static let resourceSchema: [String] = [
        "CREATE TABLE IF NOT EXISTS proc_app(id INTEGER PRIMARY KEY, key TEXT NOT NULL UNIQUE)",
        """
        CREATE TABLE IF NOT EXISTS proc_min(
          ts INTEGER NOT NULL, app INTEGER NOT NULL, cpu_ns INTEGER NOT NULL DEFAULT 0, gpu_ns INTEGER NOT NULL DEFAULT 0,
          wr_b INTEGER NOT NULL DEFAULT 0, rd_b INTEGER NOT NULL DEFAULT 0, energy_nj INTEGER NOT NULL DEFAULT 0,
          fp_b INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(ts, app)) WITHOUT ROWID
        """,
        """
        CREATE TABLE IF NOT EXISTS proc_hour(
          ts_hour INTEGER NOT NULL, app INTEGER NOT NULL, cpu_ns INTEGER NOT NULL DEFAULT 0, gpu_ns INTEGER NOT NULL DEFAULT 0,
          wr_b INTEGER NOT NULL DEFAULT 0, rd_b INTEGER NOT NULL DEFAULT 0, energy_nj INTEGER NOT NULL DEFAULT 0,
          fp_sum INTEGER NOT NULL DEFAULT 0, fp_max INTEGER NOT NULL DEFAULT 0, samples INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY(ts_hour, app)) WITHOUT ROWID
        """,
        "CREATE TABLE IF NOT EXISTS disk_free(ts INTEGER PRIMARY KEY, free_b INTEGER NOT NULL, important_b INTEGER NOT NULL DEFAULT 0)",
        """
        CREATE TABLE IF NOT EXISTS disk_dir(
          ts INTEGER NOT NULL, path TEXT NOT NULL, depth INTEGER NOT NULL, bytes INTEGER NOT NULL,
          PRIMARY KEY(ts, path)) WITHOUT ROWID
        """,
    ]

    // MARK: Yazma

    /// Bir dakikalık satırları ve boş alan değerini tek işlemde yazar. `ts` saniye (dakikaya yuvarlanmış önerilir).
    func addResourceMinute(ts: Int, rows: [KeyedUsage], freeBytes: UInt64?, importantFreeBytes: UInt64 = 0) {
        guard db != nil else { return }
        beginTransaction()
        defer { commitTransaction() }
        for r in rows {
            run("INSERT OR IGNORE INTO proc_app(key) VALUES(?)", [.text(r.key)]) { _ in }
            run("""
                INSERT INTO proc_min(ts, app, cpu_ns, gpu_ns, wr_b, rd_b, energy_nj, fp_b)
                VALUES(?, (SELECT id FROM proc_app WHERE key = ?), ?, ?, ?, ?, ?, ?)
                ON CONFLICT(ts, app) DO UPDATE SET cpu_ns = cpu_ns + excluded.cpu_ns, gpu_ns = gpu_ns + excluded.gpu_ns,
                  wr_b = wr_b + excluded.wr_b, rd_b = rd_b + excluded.rd_b, energy_nj = energy_nj + excluded.energy_nj,
                  fp_b = MAX(fp_b, excluded.fp_b)
                """,
                [.int(ts), .text(r.key), .int(Self.clamp(r.usage.cpuNs)), .int(Self.clamp(r.usage.gpuNs)),
                 .int(Self.clamp(r.usage.writeBytes)), .int(Self.clamp(r.usage.readBytes)),
                 .int(Self.clamp(r.usage.energyNj)), .int(Self.clamp(r.usage.footprint))]) { _ in }
        }
        if let freeBytes {
            run("INSERT OR REPLACE INTO disk_free(ts, free_b, important_b) VALUES(?,?,?)",
                [.int(ts), .int(Self.clamp(freeBytes)), .int(Self.clamp(importantFreeBytes))]) { _ in }
        }
    }

    /// 24 saatten eski dakikalıkları saatliğe toplar, 7 günden eskiyi siler. Saatte bir ve açılışta çağrılır.
    func resourceMaintenance(now: Date = .now) {
        guard db != nil else { return }
        let nowTs = Int(now.timeIntervalSince1970)
        let cutoff = (nowTs - Self.minuteRetentionSeconds) / 3_600 * 3_600
        let keep = nowTs - Self.resourceRetentionSeconds
        beginTransaction()
        defer { commitTransaction() }
        run("""
            INSERT INTO proc_hour(ts_hour, app, cpu_ns, gpu_ns, wr_b, rd_b, energy_nj, fp_sum, fp_max, samples)
            SELECT ts / 3600 * 3600, app, SUM(cpu_ns), SUM(gpu_ns), SUM(wr_b), SUM(rd_b), SUM(energy_nj),
                   SUM(fp_b), MAX(fp_b), COUNT(*)
            FROM proc_min WHERE ts < ? GROUP BY ts / 3600, app
            ON CONFLICT(ts_hour, app) DO UPDATE SET
              cpu_ns = cpu_ns + excluded.cpu_ns, gpu_ns = gpu_ns + excluded.gpu_ns, wr_b = wr_b + excluded.wr_b,
              rd_b = rd_b + excluded.rd_b, energy_nj = energy_nj + excluded.energy_nj,
              fp_sum = fp_sum + excluded.fp_sum, fp_max = MAX(fp_max, excluded.fp_max), samples = samples + excluded.samples
            """, [.int(cutoff)]) { _ in }
        run("DELETE FROM proc_min WHERE ts < ?", [.int(cutoff)]) { _ in }
        run("DELETE FROM proc_hour WHERE ts_hour < ?", [.int(keep)]) { _ in }
        run("DELETE FROM disk_free WHERE ts < ?", [.int(keep)]) { _ in }
        run("DELETE FROM disk_dir WHERE ts < ?", [.int(keep)]) { _ in }
        run("DELETE FROM proc_app WHERE id NOT IN (SELECT app FROM proc_min UNION SELECT app FROM proc_hour)", []) { _ in }
    }

    /// Bir klasör taramasının anlık görüntüsü (tek zaman damgası).
    func addFolderSnapshot(ts: Int, entries: [FolderSnapshotEntry]) {
        guard db != nil, !entries.isEmpty else { return }
        beginTransaction()
        defer { commitTransaction() }
        for e in entries {
            run("INSERT OR REPLACE INTO disk_dir(ts, path, depth, bytes) VALUES(?,?,?,?)",
                [.int(ts), .text(e.path), .int(e.depth), .int(Self.clamp(e.bytes))]) { _ in }
        }
    }

    // MARK: Okuma

    private struct Aggregate {
        var cpu: Double = 0, gpu: Double = 0, write: Double = 0, energy: Double = 0
        var fpMax: Double = 0, fpSum: Double = 0, samples: Double = 0

        func value(_ metric: ResourceMetric) -> Double {
            switch metric {
            case .cpu: cpu
            case .gpu: gpu
            case .diskWrite: write
            case .energy: energy
            case .memoryPeak: fpMax
            case .memoryAvg: samples > 0 ? fpSum / samples : 0
            }
        }
    }

    private static let unionSQL = """
        SELECT app, ts AS t, cpu_ns, gpu_ns, wr_b, energy_nj, fp_b AS fp_max, fp_b AS fp_sum, 1 AS samples FROM proc_min WHERE ts >= :from
        UNION ALL
        SELECT app, ts_hour AS t, cpu_ns, gpu_ns, wr_b, energy_nj, fp_max, fp_sum, samples FROM proc_hour WHERE ts_hour + 3600 > :from
        """

    /// `window` içinde ölçütte en çok kullanan uygulamalar (`__other__` hariç, değeri 0 olanlar hariç), büyükten küçüğe.
    func topConsumers(metric: ResourceMetric, window: ResourceWindow, now: Date = .now, limit: Int = 15) -> [ResourceRank] {
        let from = Int(now.timeIntervalSince1970) - window.seconds
        var out: [ResourceRank] = []
        run("""
            SELECT a.key, SUM(u.cpu_ns), SUM(u.gpu_ns), SUM(u.wr_b), SUM(u.energy_nj), MAX(u.fp_max), SUM(u.fp_sum), SUM(u.samples)
            FROM (\(Self.unionSQL.replacingOccurrences(of: ":from", with: "?"))) u JOIN proc_app a ON a.id = u.app
            WHERE a.key != '__other__' GROUP BY u.app
            """, [.int(from), .int(from)]) { s in
            let agg = Aggregate(cpu: Self.d(s, 1), gpu: Self.d(s, 2), write: Self.d(s, 3), energy: Self.d(s, 4),
                                fpMax: Self.d(s, 5), fpSum: Self.d(s, 6), samples: Self.d(s, 7))
            let v = agg.value(metric)
            if v > 0 { out.append(ResourceRank(app: Self.text(s, 0), value: v)) }
        }
        out.sort { $0.value != $1.value ? $0.value > $1.value : $0.app < $1.app }
        return Array(out.prefix(max(0, limit)))
    }

    /// Tek uygulamanın serisi. Her kova için: toplam (cpu, gpu, disk, enerji) ya da ortalama/tepe (bellek);
    /// kayıt olmayan kovalar 0.
    func resourceSeries(app: String, metric: ResourceMetric, window: ResourceWindow, now: Date = .now) -> [ResourceSeriesPoint] {
        let nowTs = Int(now.timeIntervalSince1970)
        let from = nowTs - window.seconds
        let bucket = window.bucketSeconds
        var byBucket: [Int: Aggregate] = [:]
        run("""
            SELECT t / ? * ?, SUM(cpu_ns), SUM(gpu_ns), SUM(wr_b), SUM(energy_nj), MAX(fp_max), SUM(fp_sum), SUM(samples)
            FROM (\(Self.unionSQL.replacingOccurrences(of: ":from", with: "?"))) u
            WHERE u.app = (SELECT id FROM proc_app WHERE key = ?) GROUP BY 1
            """, [.int(bucket), .int(bucket), .int(from), .int(from), .text(app)]) { s in
            byBucket[Int(sqlite3_column_int64(s, 0))] = Aggregate(cpu: Self.d(s, 1), gpu: Self.d(s, 2), write: Self.d(s, 3),
                                                                  energy: Self.d(s, 4), fpMax: Self.d(s, 5), fpSum: Self.d(s, 6),
                                                                  samples: Self.d(s, 7))
        }
        var points: [ResourceSeriesPoint] = []
        var t = from / bucket * bucket
        while t <= nowTs {
            points.append(ResourceSeriesPoint(ts: t, value: byBucket[t]?.value(metric) ?? 0))
            t += bucket
        }
        return points
    }

    /// Son `minutes` dakikada ölçütte en çok kullananlar (Genel bakış kartı; dakikalık tablodan).
    func recentTop(metric: ResourceMetric, minutes: Int = 5, now: Date = .now, limit: Int = 3) -> [ResourceRank] {
        topRecent(metric: metric, seconds: minutes * 60, now: now, limit: limit)
    }

    private func topRecent(metric: ResourceMetric, seconds: Int, now: Date, limit: Int) -> [ResourceRank] {
        let from = Int(now.timeIntervalSince1970) - seconds
        var out: [ResourceRank] = []
        run("""
            SELECT a.key, SUM(m.cpu_ns), SUM(m.gpu_ns), SUM(m.wr_b), SUM(m.energy_nj), MAX(m.fp_b), SUM(m.fp_b), COUNT(*)
            FROM proc_min m JOIN proc_app a ON a.id = m.app WHERE m.ts >= ? AND a.key != '__other__' GROUP BY m.app
            """, [.int(from)]) { s in
            let agg = Aggregate(cpu: Self.d(s, 1), gpu: Self.d(s, 2), write: Self.d(s, 3), energy: Self.d(s, 4),
                                fpMax: Self.d(s, 5), fpSum: Self.d(s, 6), samples: Self.d(s, 7))
            let v = agg.value(metric)
            if v > 0 { out.append(ResourceRank(app: Self.text(s, 0), value: v)) }
        }
        out.sort { $0.value != $1.value ? $0.value > $1.value : $0.app < $1.app }
        return Array(out.prefix(max(0, limit)))
    }

    /// "Uygulama geçmişi" tablosu: pencere boyunca uygulama başına tüm ölçütler (`__other__` hariç).
    /// Ağ baytları saatlik kullanım tablosundan gelir (saat çözünürlüğü; pencere başı saate yuvarlanır).
    func appHistoryRows(window: ResourceWindow, now: Date = .now) -> [AppHistoryRow] {
        let from = Int(now.timeIntervalSince1970) - window.seconds
        var rows: [String: AppHistoryRow] = [:]
        run("""
            SELECT a.key, SUM(u.cpu_ns), SUM(u.gpu_ns), SUM(u.wr_b), SUM(u.energy_nj), MAX(u.fp_max)
            FROM (\(Self.unionSQL.replacingOccurrences(of: ":from", with: "?"))) u JOIN proc_app a ON a.id = u.app
            WHERE a.key != '__other__' GROUP BY u.app
            """, [.int(from), .int(from)]) { s in
            let key = Self.text(s, 0)
            rows[key] = AppHistoryRow(app: key, cpuNs: Self.d(s, 1), gpuNs: Self.d(s, 2), writeBytes: Self.d(s, 3),
                                      energyNj: Self.d(s, 4), memoryPeak: Self.d(s, 5), networkBytes: 0)
        }
        run("""
            SELECT app, SUM(bytes_in + bytes_out) FROM usage_hourly WHERE hour >= ? AND app != ? GROUP BY app
            """, [.int(from / 3_600 * 3_600), .text(Self.interfaceAppKey)]) { s in
            let key = Self.text(s, 0)
            let bytes = Self.d(s, 1)
            guard bytes > 0 else { return }
            var row = rows[key] ?? AppHistoryRow(app: key, cpuNs: 0, gpuNs: 0, writeBytes: 0, energyNj: 0, memoryPeak: 0, networkBytes: 0)
            row.networkBytes = bytes
            rows[key] = row
        }
        return Array(rows.values.filter { $0.hasActivity })
    }

    /// Tüm uygulamaların (`__other__` dahil, yani sistemin tamamı) kova başına toplamı: Performans sekmesinin 1 sa / 24 sa grafikleri.
    /// Kayıt olmayan kovalar 0. Bellek: kova içindeki dakikalık "uygulama ayak izi" toplamlarının ortalaması.
    func resourceTotalSeries(window: ResourceWindow, now: Date = .now) -> [ResourceTotalPoint] {
        let nowTs = Int(now.timeIntervalSince1970)
        let from = nowTs - window.seconds
        let bucket = window.bucketSeconds
        var byBucket: [Int: ResourceTotalPoint] = [:]
        var minuteCount: [Int: Int] = [:]
        run("""
            SELECT t, SUM(cpu_ns), SUM(gpu_ns), SUM(wr_b), SUM(rd_b), SUM(fp_max) FROM (
              SELECT ts AS t, cpu_ns, gpu_ns, wr_b, rd_b, fp_b AS fp_max FROM proc_min WHERE ts >= ?
              UNION ALL
              SELECT ts_hour AS t, cpu_ns, gpu_ns, wr_b, rd_b, fp_max FROM proc_hour WHERE ts_hour + 3600 > ?
            ) GROUP BY t
            """, [.int(from), .int(from)]) { s in
            let t = Int(sqlite3_column_int64(s, 0)) / bucket * bucket
            var p = byBucket[t] ?? ResourceTotalPoint(ts: t)
            p.cpuNs += Self.d(s, 1)
            p.gpuNs += Self.d(s, 2)
            p.writeBytes += Self.d(s, 3)
            p.readBytes += Self.d(s, 4)
            p.footprint += Self.d(s, 5)
            byBucket[t] = p
            minuteCount[t, default: 0] += 1
        }
        var points: [ResourceTotalPoint] = []
        var t = from / bucket * bucket
        while t <= nowTs {
            var p = byBucket[t] ?? ResourceTotalPoint(ts: t)
            if let n = minuteCount[t], n > 1 { p.footprint /= Double(n) }
            points.append(p)
            t += bucket
        }
        return points
    }

    /// Dakikalık kaydın en eskisi / en yenisi (boşsa nil); boş durum metinleri için.
    func resourceTimeRange() -> (first: Int, last: Int)? {
        var result: (Int, Int)?
        run("SELECT MIN(t), MAX(t) FROM (SELECT ts AS t FROM proc_min UNION ALL SELECT ts_hour FROM proc_hour)", []) { s in
            if sqlite3_column_type(s, 0) != SQLITE_NULL { result = (Int(sqlite3_column_int64(s, 0)), Int(sqlite3_column_int64(s, 1))) }
        }
        return result
    }

    func diskFreeSeries(window: ResourceWindow, now: Date = .now) -> [DiskFreePoint] {
        let from = Int(now.timeIntervalSince1970) - window.seconds
        let bucket = max(60, window.seconds / 120)
        var out: [DiskFreePoint] = []
        run("SELECT ts / ? * ?, MIN(free_b) FROM disk_free WHERE ts >= ? GROUP BY 1 ORDER BY 1",
            [.int(bucket), .int(bucket), .int(from)]) { s in
            out.append(DiskFreePoint(ts: Int(sqlite3_column_int64(s, 0)), freeBytes: Self.u64(s, 1)))
        }
        return out
    }

    struct FolderGrowthReport: Sendable, Equatable {
        var items: [FolderGrowth] = []
        /// Karşılaştırma tabanı ve en son tarama (epoch sn); tarama yoksa nil.
        var baseTs: Int?
        var latestTs: Int?
        /// Karşılaştıracak ikinci bir tarama yok.
        var hasComparison: Bool { baseTs != nil && latestTs != nil && baseTs != latestTs }
    }

    /// Klasör büyümesi: en son tarama ile `window` başındaki (ya da ondan önceki son / yoksa en eski) tarama arası fark.
    /// Yalnızca büyüyenler, büyümeye göre sıralı; üst/alt klasör çiftleri birleştirilir.
    func folderGrowth(window: ResourceWindow, now: Date = .now, limit: Int = 15) -> FolderGrowthReport {
        var latest: Int?
        run("SELECT MAX(ts) FROM disk_dir", []) { s in
            if sqlite3_column_type(s, 0) != SQLITE_NULL { latest = Int(sqlite3_column_int64(s, 0)) }
        }
        guard let latest else { return FolderGrowthReport() }
        let from = Int(now.timeIntervalSince1970) - window.seconds
        var base: Int?
        run("SELECT MAX(ts) FROM disk_dir WHERE ts <= ? AND ts < ?", [.int(from), .int(latest)]) { s in
            if sqlite3_column_type(s, 0) != SQLITE_NULL { base = Int(sqlite3_column_int64(s, 0)) }
        }
        if base == nil {
            run("SELECT MIN(ts) FROM disk_dir WHERE ts < ?", [.int(latest)]) { s in
                if sqlite3_column_type(s, 0) != SQLITE_NULL { base = Int(sqlite3_column_int64(s, 0)) }
            }
        }
        var report = FolderGrowthReport(items: [], baseTs: base ?? latest, latestTs: latest)
        guard let base else { return report }
        var before: [String: UInt64] = [:]
        run("SELECT path, bytes FROM disk_dir WHERE ts = ?", [.int(base)]) { s in before[Self.text(s, 0)] = Self.u64(s, 1) }
        // Tabanda kaydı olmayan alt klasör "eşikten küçüktü" demektir (taramalar yalnız ≥ eşik kaydeder); büyüme eşikten sayılır.
        // Kökler (depth 0) her zaman kayıtlıdır.
        let floor = Self.recordingThreshold
        var items: [FolderGrowth] = []
        run("SELECT path, depth, bytes FROM disk_dir WHERE ts = ?", [.int(latest)]) { s in
            let path = Self.text(s, 0)
            let cur = Self.u64(s, 2)
            let depth = Int(sqlite3_column_int(s, 1))
            let growth = Int64(clamping: cur) - Int64(clamping: before[path] ?? (depth == 0 ? 0 : floor))
            if growth > 0 { items.append(FolderGrowth(path: path, depth: depth, currentBytes: cur, growthBytes: growth)) }
        }
        items = FolderGrowthCollapse.collapse(items)
        items.sort { $0.growthBytes != $1.growthBytes ? $0.growthBytes > $1.growthBytes : $0.path < $1.path }
        report.items = Array(items.prefix(max(0, limit)))
        return report
    }

    /// En son anlık görüntüdeki, verilen köklerin altındaki (kökün kendisi dahil) girdiler. Taranmayan (seyrek) köklerin
    /// değeri yeni anlık görüntüye taşınır; böylece her anlık görüntü eksiksizdir.
    func latestFolderEntries(underRoots roots: [String]) -> [FolderSnapshotEntry] {
        guard !roots.isEmpty else { return [] }
        var out: [FolderSnapshotEntry] = []
        run("SELECT path, depth, bytes FROM disk_dir WHERE ts = (SELECT MAX(ts) FROM disk_dir)", []) { s in
            let path = Self.text(s, 0)
            if roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                out.append(FolderSnapshotEntry(path: path, depth: Int(sqlite3_column_int(s, 1)), bytes: Self.u64(s, 2)))
            }
        }
        return out
    }

    /// En son klasör taramasının zamanı (epoch sn), yoksa nil.
    func lastFolderScan() -> Int? {
        var result: Int?
        run("SELECT MAX(ts) FROM disk_dir", []) { s in
            if sqlite3_column_type(s, 0) != SQLITE_NULL { result = Int(sqlite3_column_int64(s, 0)) }
        }
        return result
    }

    /// Test/denetim: tablo satır sayıları.
    func resourceRowCounts() -> (minute: Int, hour: Int, apps: Int) {
        var m = 0, h = 0, a = 0
        run("SELECT (SELECT COUNT(*) FROM proc_min), (SELECT COUNT(*) FROM proc_hour), (SELECT COUNT(*) FROM proc_app)", []) { s in
            m = Int(sqlite3_column_int64(s, 0)); h = Int(sqlite3_column_int64(s, 1)); a = Int(sqlite3_column_int64(s, 2))
        }
        return (m, h, a)
    }

    // MARK: Yardımcılar

    private func beginTransaction() { sqlite3_exec(db, "BEGIN", nil, nil, nil) }
    private func commitTransaction() { sqlite3_exec(db, "COMMIT", nil, nil, nil) }
    private static func clamp(_ v: UInt64) -> Int { Int(clamping: v) }
    private static func d(_ s: OpaquePointer?, _ col: Int32) -> Double { Double(max(0, sqlite3_column_int64(s, col))) }
}
