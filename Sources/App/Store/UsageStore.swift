import Foundation
import SQLite3

/// Günlük ve saatlik kullanım kaydı (SQLite). Tüm erişim bu actor üzerinden.
actor UsageStore {
    struct Row: Sendable {
        var app: String
        var host: String
        var mobile: Bool
        var bytesIn: UInt64
        var bytesOut: UInt64
    }

    /// Saatlik satır. `hour` saat başının epoch saniyesi; `domain` yoksa nil (veritabanında boş metin).
    struct HourlyRow: Sendable, Equatable {
        var hour: Int
        var app: String
        var domain: String?
        var mobile: Bool
        var bytesIn: UInt64
        var bytesOut: UInt64
    }

    /// Saatlik tabloda fiziksel arayüz toplamlarını taşıyan ayrılmış uygulama anahtarı (grafikler uygulama
    /// toplamı yerine bunu kullanır; günlük limitle aynı kaynak). Bayt `bytes_in` sütununa yazılır (giriş+çıkış).
    static let interfaceAppKey = "__iface__"
    /// Saatlik satırlar bu kadar günden sonra silinir.
    static let hourlyRetentionDays = 60

    struct HourPoint: Sendable, Equatable {
        var hour: Int
        var mobileBytes: UInt64
        var otherBytes: UInt64
        var total: UInt64 { mobileBytes + otherBytes }
    }

    struct AppHourBytes: Sendable, Equatable {
        var app: String
        var bytes: UInt64
        var mobileBytes: UInt64
    }

    struct DayPoint: Sendable, Equatable {
        var day: String
        var mobileBytes: UInt64
        var otherBytes: UInt64
    }

    struct DomainBytes: Sendable, Equatable {
        var name: String
        var bytes: UInt64
    }

    /// Gün anahtarlarının ve "bugün" sınırlarının hesaplandığı takvim: Gregoryen, kullanıcının yerel saat dilimi
    /// (sistem saat dilimi değişince kendiliğinden güncellenir). Gün anahtarı biçimi her zaman `yyyy-MM-dd`.
    /// Eski satırlar GMT günlerine göre yazılmıştı; taşınmadı (yalnız geçiş günü örtüşebilir).
    /// Testler `calendar:` parametresiyle başka bir takvim (ör. Europe/Berlin) verir.
    static var keyCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .autoupdatingCurrent
        return c
    }

    /// `UsageStore+Resources` ile paylaşılır (aynı dosya, aynı bağlantı).
    var db: OpaquePointer?

    /// - Parameter path: Veritabanı dosyası. Varsayılan: Application Support (testlerde geçici dizin).
    init(path: String? = nil) {
        let path = path ?? AppEnvironment.supportDirectory.appending(path: "usage.sqlite").path
        var handle: OpaquePointer?
        if sqlite3_open(path, &handle) == SQLITE_OK {
            db = handle
            for sql in [
                "PRAGMA journal_mode=WAL",
                """
                CREATE TABLE IF NOT EXISTS usage(
                  day TEXT NOT NULL, app TEXT NOT NULL, host TEXT NOT NULL, mobile INTEGER NOT NULL,
                  bytes_in INTEGER NOT NULL DEFAULT 0, bytes_out INTEGER NOT NULL DEFAULT 0,
                  PRIMARY KEY(day, app, host, mobile))
                """,
                """
                CREATE TABLE IF NOT EXISTS iface_daily(
                  day TEXT NOT NULL, mobile INTEGER NOT NULL, bytes INTEGER NOT NULL DEFAULT 0,
                  PRIMARY KEY(day, mobile))
                """,
                // domain NULL yerine '' (PRIMARY KEY'de NULL'lar ayrı sayılır, upsert birleştirmez).
                """
                CREATE TABLE IF NOT EXISTS usage_hourly(
                  hour INTEGER NOT NULL, app TEXT NOT NULL, domain TEXT NOT NULL DEFAULT '', mobile INTEGER NOT NULL,
                  bytes_in INTEGER NOT NULL DEFAULT 0, bytes_out INTEGER NOT NULL DEFAULT 0,
                  PRIMARY KEY(hour, app, domain, mobile))
                """,
            ] + Self.resourceSchema + Self.batterySchema { sqlite3_exec(handle, sql, nil, nil, nil) }
        }
    }

    /// `date`'in `calendar` takvimindeki (varsayılan: yerel) gün anahtarı, `yyyy-MM-dd`.
    static func dayKey(_ date: Date = .now, calendar: Calendar = UsageStore.keyCalendar) -> String {
        BudgetCalculator.dayKey(date, calendar: calendar)
    }

    // MARK: Yazma

    /// Günlük satırları ve (varsa) saatlik satırları tek işlemde yazar.
    func add(day: String, rows: [Row], hourly: [HourlyRow] = []) {
        guard let db, !rows.isEmpty || !hourly.isEmpty else { return }
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }
        if !rows.isEmpty {
            let sql = """
            INSERT INTO usage(day, app, host, mobile, bytes_in, bytes_out) VALUES(?,?,?,?,?,?)
            ON CONFLICT(day, app, host, mobile) DO UPDATE SET
              bytes_in = bytes_in + excluded.bytes_in, bytes_out = bytes_out + excluded.bytes_out
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                for r in rows {
                    sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, r.app, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 3, r.host, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(stmt, 4, r.mobile ? 1 : 0)
                    sqlite3_bind_int64(stmt, 5, Int64(clamping: r.bytesIn))
                    sqlite3_bind_int64(stmt, 6, Int64(clamping: r.bytesOut))
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                }
            }
            sqlite3_finalize(stmt)
        }
        if !hourly.isEmpty {
            let sql = """
            INSERT INTO usage_hourly(hour, app, domain, mobile, bytes_in, bytes_out) VALUES(?,?,?,?,?,?)
            ON CONFLICT(hour, app, domain, mobile) DO UPDATE SET
              bytes_in = bytes_in + excluded.bytes_in, bytes_out = bytes_out + excluded.bytes_out
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                for r in hourly {
                    sqlite3_bind_int64(stmt, 1, Int64(r.hour))
                    sqlite3_bind_text(stmt, 2, r.app, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 3, r.domain ?? "", -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(stmt, 4, r.mobile ? 1 : 0)
                    sqlite3_bind_int64(stmt, 5, Int64(clamping: r.bytesIn))
                    sqlite3_bind_int64(stmt, 6, Int64(clamping: r.bytesOut))
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                }
            }
            sqlite3_finalize(stmt)
        }
    }

    func addInterfaceBytes(day: String, mobile: Bool, bytes: UInt64) {
        guard let db, bytes > 0 else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO iface_daily(day, mobile, bytes) VALUES(?,?,?) ON CONFLICT(day, mobile) DO UPDATE SET bytes = bytes + excluded.bytes"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, mobile ? 1 : 0)
        sqlite3_bind_int64(stmt, 3, Int64(clamping: bytes))
        sqlite3_step(stmt)
    }

    /// Fiziksel arayüzün saatlik mobil / diğer toplamlarını yazar (`interfaceAppKey` satırları).
    func addInterfaceHourly(_ items: [(hour: Int, mobile: UInt64, other: UInt64)]) {
        var rows: [HourlyRow] = []
        for i in items {
            if i.mobile > 0 { rows.append(HourlyRow(hour: i.hour, app: Self.interfaceAppKey, domain: nil, mobile: true, bytesIn: i.mobile, bytesOut: 0)) }
            if i.other > 0 { rows.append(HourlyRow(hour: i.hour, app: Self.interfaceAppKey, domain: nil, mobile: false, bytesIn: i.other, bytesOut: 0)) }
        }
        add(day: "", rows: [], hourly: rows)
    }

    /// `hourlyRetentionDays`'ten eski saatlik satırları siler. Açılışta bir kez çağrılır.
    func pruneHourly(now: Date = .now) {
        let cutoff = Int(now.timeIntervalSince1970) - Self.hourlyRetentionDays * 86_400
        run("DELETE FROM usage_hourly WHERE hour < ?", [.int(cutoff)]) { _ in }
    }

    // MARK: Okuma (günlük)

    func rows(day: String) -> [Row] {
        var out: [Row] = []
        run("SELECT app, host, mobile, bytes_in, bytes_out FROM usage WHERE day = ?", [.text(day)]) { s in
            out.append(Row(app: Self.text(s, 0), host: Self.text(s, 1), mobile: sqlite3_column_int(s, 2) != 0,
                           bytesIn: Self.u64(s, 3), bytesOut: Self.u64(s, 4)))
        }
        return out
    }

    func interfaceBytes(day: String, mobile: Bool) -> UInt64 {
        var result: UInt64 = 0
        run("SELECT bytes FROM iface_daily WHERE day = ? AND mobile = ?", [.text(day), .int(mobile ? 1 : 0)]) { s in result = Self.u64(s, 0) }
        return result
    }

    /// `fromDay`...`toDay` (ikisi dahil, `yyyy-MM-dd`) arası fiziksel arayüz toplamı. `fromDay > toDay` ise 0.
    func interfaceBytes(fromDay: String, toDay: String, mobile: Bool) -> UInt64 {
        var result: UInt64 = 0
        run("SELECT COALESCE(SUM(bytes), 0) FROM iface_daily WHERE mobile = ? AND day BETWEEN ? AND ?",
            [.int(mobile ? 1 : 0), .text(fromDay), .text(toDay)]) { s in result = Self.u64(s, 0) }
        return result
    }

    /// Günlük toplam seri (fiziksel arayüz): her gün için mobil ve diğer byte. Verisi olmayan günler yoktur.
    func dailyTotals(fromDay: String, toDay: String) -> [DayPoint] {
        var byDay: [String: DayPoint] = [:]
        run("SELECT day, mobile, bytes FROM iface_daily WHERE day BETWEEN ? AND ? ORDER BY day", [.text(fromDay), .text(toDay)]) { s in
            let day = Self.text(s, 0)
            var p = byDay[day] ?? DayPoint(day: day, mobileBytes: 0, otherBytes: 0)
            if sqlite3_column_int(s, 1) != 0 { p.mobileBytes += Self.u64(s, 2) } else { p.otherBytes += Self.u64(s, 2) }
            byDay[day] = p
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// Bir uygulamanın günlük serisi (günlük `usage` tablosundan): mobil ve diğer byte.
    func dailySeries(app: String, fromDay: String, toDay: String) -> [DayPoint] {
        var out: [DayPoint] = []
        run("""
            SELECT day, SUM(CASE WHEN mobile != 0 THEN bytes_in + bytes_out ELSE 0 END),
                   SUM(CASE WHEN mobile = 0 THEN bytes_in + bytes_out ELSE 0 END)
            FROM usage WHERE app = ? AND day BETWEEN ? AND ? GROUP BY day ORDER BY day
            """, [.text(app), .text(fromDay), .text(toDay)]) { s in
            out.append(DayPoint(day: Self.text(s, 0), mobileBytes: Self.u64(s, 1), otherBytes: Self.u64(s, 2)))
        }
        return out
    }

    /// Bir uygulamanın `fromDay`...`toDay` aralığında en çok kullanılan alan adı grupları (`DomainGrouper` ile gruplanır).
    func topDomains(app: String, fromDay: String, toDay: String, limit: Int = 10) -> [DomainBytes] {
        var raw: [String: UInt64] = [:]
        run("SELECT host, SUM(bytes_in + bytes_out) FROM usage WHERE app = ? AND day BETWEEN ? AND ? GROUP BY host",
            [.text(app), .text(fromDay), .text(toDay)]) { s in
            raw[DomainGrouper.group(Self.text(s, 0)), default: 0] += Self.u64(s, 1)
        }
        return DomainGrouper.displayOrder(raw.map { DomainBytes(name: $0.key, bytes: $0.value) }, limit: limit,
                                          name: \.name, bytes: \.bytes)
    }

    /// `fromDay`...`toDay` aralığında en çok kullanan uygulamalar (günlük `usage` tablosundan; mobil payıyla).
    /// Eski günler için de çalışır (saatlik kayıt gerekmez).
    func topApps(fromDay: String, toDay: String, limit: Int = 10) -> [AppHourBytes] {
        var out: [AppHourBytes] = []
        run("""
            SELECT app, SUM(bytes_in + bytes_out), SUM(CASE WHEN mobile != 0 THEN bytes_in + bytes_out ELSE 0 END)
            FROM usage WHERE day BETWEEN ? AND ? GROUP BY app ORDER BY 2 DESC, app LIMIT ?
            """, [.text(fromDay), .text(toDay), .int(max(0, limit))]) { s in
            out.append(AppHourBytes(app: Self.text(s, 0), bytes: Self.u64(s, 1), mobileBytes: Self.u64(s, 2)))
        }
        return out
    }

    /// `fromDay`...`toDay` aralığında tüm uygulamalarda en çok kullanılan alan adı grupları (`DomainGrouper` ile gruplanır).
    func topDomains(fromDay: String, toDay: String, limit: Int = 10) -> [DomainBytes] {
        var raw: [String: UInt64] = [:]
        run("SELECT host, SUM(bytes_in + bytes_out) FROM usage WHERE day BETWEEN ? AND ? GROUP BY host",
            [.text(fromDay), .text(toDay)]) { s in
            raw[DomainGrouper.group(Self.text(s, 0)), default: 0] += Self.u64(s, 1)
        }
        return DomainGrouper.displayOrder(raw.map { DomainBytes(name: $0.key, bytes: $0.value) }, limit: limit,
                                          name: \.name, bytes: \.bytes)
    }

    /// `fromDay`...`toDay` aralığında uygulamalara atfedilen toplam bayt (`usage` tablosu; arayüz toplamından düşük olabilir).
    func attributedBytes(fromDay: String, toDay: String) -> UInt64 {
        var result: UInt64 = 0
        run("SELECT COALESCE(SUM(bytes_in + bytes_out), 0) FROM usage WHERE day BETWEEN ? AND ?",
            [.text(fromDay), .text(toDay)]) { s in result = Self.u64(s, 0) }
        return result
    }

    // MARK: Okuma (saatlik)

    /// `[from, to)` saat başı epoch aralığında fiziksel arayüz saatlik toplamı (günlük limitle aynı kaynak).
    func interfaceHourly(from: Int, to: Int) -> [HourPoint] {
        hourly("""
               SELECT hour, mobile, SUM(bytes_in + bytes_out) FROM usage_hourly
               WHERE app = ? AND hour >= ? AND hour < ? GROUP BY hour, mobile ORDER BY hour
               """, [.text(Self.interfaceAppKey), .int(from), .int(to)])
    }

    /// `[from, to)` aralığında uygulama bazlı toplamların saatlik serisi (arayüz satırları hariç).
    func appsHourlyTotal(from: Int, to: Int) -> [HourPoint] {
        hourly("""
               SELECT hour, mobile, SUM(bytes_in + bytes_out) FROM usage_hourly
               WHERE app != ? AND hour >= ? AND hour < ? GROUP BY hour, mobile ORDER BY hour
               """, [.text(Self.interfaceAppKey), .int(from), .int(to)])
    }

    /// Bir uygulamanın `[from, to)` aralığındaki saatlik serisi.
    func hourlySeries(app: String, from: Int, to: Int) -> [HourPoint] {
        hourly("""
               SELECT hour, mobile, SUM(bytes_in + bytes_out) FROM usage_hourly
               WHERE app = ? AND hour >= ? AND hour < ? GROUP BY hour, mobile ORDER BY hour
               """, [.text(app), .int(from), .int(to)])
    }

    /// Saatlik tablodaki en eski saat başı (epoch sn); tablo boşsa nil. Saatlik kaydın ne zaman başladığını gösterir.
    func firstHourlyRecord() -> Int? {
        var result: Int?
        run("SELECT MIN(hour) FROM usage_hourly", []) { s in
            if sqlite3_column_type(s, 0) != SQLITE_NULL { result = Int(sqlite3_column_int64(s, 0)) }
        }
        return result
    }

    /// Bir saatte (saat başı epoch) en çok kullanan uygulamalar.
    func topApps(hour: Int, limit: Int = 10) -> [AppHourBytes] {
        var out: [AppHourBytes] = []
        run("""
            SELECT app, SUM(bytes_in + bytes_out), SUM(CASE WHEN mobile != 0 THEN bytes_in + bytes_out ELSE 0 END)
            FROM usage_hourly WHERE hour = ? AND app != ? GROUP BY app ORDER BY 2 DESC, app LIMIT ?
            """, [.int(hour), .text(Self.interfaceAppKey), .int(max(0, limit))]) { s in
            out.append(AppHourBytes(app: Self.text(s, 0), bytes: Self.u64(s, 1), mobileBytes: Self.u64(s, 2)))
        }
        return out
    }

    /// Bir uygulamanın bir saatteki alan adı dağılımı (boş alan adı `nil`). Eski satırlarda ham IP olarak kalmış adlar
    /// okunurken yeniden gruplanır (yerel adresler "Yerel ağ"da birleşir); sıra: adlı alan adları, proxy, IP, yerel ağ.
    func hourlyDomains(app: String, hour: Int) -> [(domain: String?, bytes: UInt64)] {
        var merged: [String: UInt64] = [:]
        var other: UInt64 = 0
        run("SELECT domain, SUM(bytes_in + bytes_out) FROM usage_hourly WHERE hour = ? AND app = ? GROUP BY domain",
            [.int(hour), .text(app)]) { s in
            let d = Self.text(s, 0)
            if d.isEmpty { other += Self.u64(s, 1) } else { merged[DomainGrouper.group(d), default: 0] += Self.u64(s, 1) }
        }
        var rows: [(domain: String?, bytes: UInt64)] = merged.map { ($0.key, $0.value) }
        if other > 0 { rows.append((nil, other)) }
        return DomainGrouper.displayOrder(rows, limit: rows.count,
                                          name: { $0.domain ?? DomainGrouper.unknownName }, bytes: \.bytes)
    }

    /// Test/denetim: tüm saatlik satırlar.
    func allHourlyRows() -> [HourlyRow] {
        var out: [HourlyRow] = []
        run("SELECT hour, app, domain, mobile, bytes_in, bytes_out FROM usage_hourly ORDER BY hour, app, domain, mobile", []) { s in
            let d = Self.text(s, 2)
            out.append(HourlyRow(hour: Int(sqlite3_column_int64(s, 0)), app: Self.text(s, 1), domain: d.isEmpty ? nil : d,
                                 mobile: sqlite3_column_int(s, 3) != 0, bytesIn: Self.u64(s, 4), bytesOut: Self.u64(s, 5)))
        }
        return out
    }

    // MARK: Yardımcılar

    enum Bind { case text(String), int(Int) }

    private func hourly(_ sql: String, _ binds: [Bind]) -> [HourPoint] {
        var byHour: [Int: HourPoint] = [:]
        run(sql, binds) { s in
            let h = Int(sqlite3_column_int64(s, 0))
            var p = byHour[h] ?? HourPoint(hour: h, mobileBytes: 0, otherBytes: 0)
            if sqlite3_column_int(s, 1) != 0 { p.mobileBytes += Self.u64(s, 2) } else { p.otherBytes += Self.u64(s, 2) }
            byHour[h] = p
        }
        return byHour.values.sorted { $0.hour < $1.hour }
    }

    @discardableResult
    func run(_ sql: String, _ binds: [Bind], row: (OpaquePointer?) -> Void) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in binds.enumerated() {
            switch b {
            case .text(let t): sqlite3_bind_text(stmt, Int32(i + 1), t, -1, SQLITE_TRANSIENT)
            case .int(let n): sqlite3_bind_int64(stmt, Int32(i + 1), Int64(n))
            }
        }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { row(stmt) } else { return rc == SQLITE_DONE }
        }
    }

    static func text(_ s: OpaquePointer?, _ col: Int32) -> String {
        sqlite3_column_text(s, col).map { String(cString: $0) } ?? ""
    }

    static func u64(_ s: OpaquePointer?, _ col: Int32) -> UInt64 {
        UInt64(max(0, sqlite3_column_int64(s, col)))
    }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
