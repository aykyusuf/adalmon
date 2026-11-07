import Foundation
import SQLite3

/// Dakikalık pil örneği (pil seviyesi grafiği, sıcaklık, güç).
struct BatterySample: Sendable, Equatable, Identifiable {
    var ts: Int
    var pct: Int
    var charging: Bool
    var plugged: Bool
    var tempC: Double?
    var voltageMV: Int?
    var amperageMA: Int?
    var systemMW: Int?
    var adapterW: Int?
    var rawMaxMAh: Int?
    var nominalMAh: Int?
    var cycles: Int?
    var id: Int { ts }

    init(ts: Int, pct: Int, charging: Bool = false, plugged: Bool = false, tempC: Double? = nil, voltageMV: Int? = nil,
         amperageMA: Int? = nil, systemMW: Int? = nil, adapterW: Int? = nil, rawMaxMAh: Int? = nil, nominalMAh: Int? = nil, cycles: Int? = nil) {
        self.ts = ts; self.pct = pct; self.charging = charging; self.plugged = plugged; self.tempC = tempC
        self.voltageMV = voltageMV; self.amperageMA = amperageMA; self.systemMW = systemMW; self.adapterW = adapterW
        self.rawMaxMAh = rawMaxMAh; self.nominalMAh = nominalMAh; self.cycles = cycles
    }

    init(_ r: BatteryReading) {
        self.init(ts: Int(r.timestamp.timeIntervalSince1970), pct: r.level, charging: r.isCharging, plugged: r.isPluggedIn,
                  tempC: r.temperatureC, voltageMV: r.voltageMV, amperageMA: r.amperageMA, systemMW: r.systemPowerMW,
                  adapterW: r.adapterWatts, rawMaxMAh: r.rawMaxMAh, nominalMAh: r.nominalMAh, cycles: r.cycles)
    }
}

/// Günlük toplam: enerji (% pil), ekran açık süresi, kapasite ve döngü.
struct BatteryDayRow: Sendable, Equatable, Identifiable {
    var day: String
    var consumedPercent: Double
    var chargedPercent: Double
    var screenSeconds: Int
    var maxCapacityMAh: Int?
    var nominalMAh: Int?
    var cycles: Int?
    var minPercent: Int?
    var maxPercent: Int?
    var avgTemp: Double?
    var minTemp: Double?
    var maxTemp: Double?
    var id: String { day }
}

extension UsageStore {
    static let batteryMinuteRetentionDays = 14
    static let batteryDailyRetentionDays = 400

    static let batterySchema: [String] = [
        """
        CREATE TABLE IF NOT EXISTS battery_min(
          ts INTEGER PRIMARY KEY, pct INTEGER NOT NULL, charging INTEGER NOT NULL DEFAULT 0, plugged INTEGER NOT NULL DEFAULT 0,
          temp_x10 INTEGER, mv INTEGER, ma INTEGER, sys_mw INTEGER, adapter_w INTEGER, raw_max INTEGER, nominal INTEGER, cycles INTEGER)
        """,
        """
        CREATE TABLE IF NOT EXISTS battery_daily(
          day TEXT PRIMARY KEY, consumed REAL NOT NULL DEFAULT 0, charged REAL NOT NULL DEFAULT 0, screen_s INTEGER NOT NULL DEFAULT 0,
          max_cap INTEGER, nominal INTEGER, cycles INTEGER, min_pct INTEGER, max_pct INTEGER,
          temp_sum INTEGER NOT NULL DEFAULT 0, temp_n INTEGER NOT NULL DEFAULT 0, temp_min INTEGER, temp_max INTEGER)
        """,
    ]

    private enum BB { case int(Int), real(Double), text(String), null }

    private func bexec(_ sql: String, _ binds: [BB]) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in binds.enumerated() {
            let c = Int32(i + 1)
            switch b {
            case .int(let v): sqlite3_bind_int64(stmt, c, Int64(v))
            case .real(let v): sqlite3_bind_double(stmt, c, v)
            case .text(let v): sqlite3_bind_text(stmt, c, v, -1, SQLITE_TRANSIENT)
            case .null: sqlite3_bind_null(stmt, c)
            }
        }
        sqlite3_step(stmt)
    }

    private static func opt(_ v: Int?) -> BB { v.map { .int($0) } ?? .null }

    private struct DayAgg {
        var consumed = 0.0, charged = 0.0, screen = 0
        var maxCap: Int?, nominal: Int?, cycles: Int?
        var minPct: Int?, maxPct: Int?
        var tempSum = 0, tempN = 0
        var tempMin: Int?, tempMax: Int?
    }

    /// Bir toplu yazım: örnekler + enerji farkları + ekran süreleri tek işlemde; günlük toplamlar yerinde güncellenir.
    func recordBattery(samples: [BatterySample], deltas: [BatteryEnergyTracker.Delta] = [],
                       screen: [ScreenOnClock.DaySeconds] = [], calendar: Calendar = UsageStore.keyCalendar) {
        guard let db, !samples.isEmpty || !deltas.isEmpty || !screen.isEmpty else { return }
        var days: [String: DayAgg] = [:]
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }
        for s in samples {
            bexec("""
                INSERT OR REPLACE INTO battery_min(ts, pct, charging, plugged, temp_x10, mv, ma, sys_mw, adapter_w, raw_max, nominal, cycles)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                """, [.int(s.ts), .int(s.pct), .int(s.charging ? 1 : 0), .int(s.plugged ? 1 : 0),
                      Self.opt(s.tempC.map { Int(($0 * 10).rounded()) }), Self.opt(s.voltageMV), Self.opt(s.amperageMA),
                      Self.opt(s.systemMW), Self.opt(s.adapterW), Self.opt(s.rawMaxMAh), Self.opt(s.nominalMAh), Self.opt(s.cycles)])
            let day = Self.dayKey(Date(timeIntervalSince1970: TimeInterval(s.ts)), calendar: calendar)
            var a = days[day] ?? DayAgg()
            if let m = s.rawMaxMAh { a.maxCap = m }
            if let n = s.nominalMAh { a.nominal = n }
            if let c = s.cycles { a.cycles = c }
            a.minPct = min(a.minPct ?? s.pct, s.pct)
            a.maxPct = max(a.maxPct ?? s.pct, s.pct)
            if let t = s.tempC {
                let x = Int((t * 10).rounded())
                a.tempSum += x; a.tempN += 1
                a.tempMin = min(a.tempMin ?? x, x); a.tempMax = max(a.tempMax ?? x, x)
            }
            days[day] = a
        }
        for d in deltas {
            days[d.day, default: DayAgg()].consumed += d.consumedPercent
            days[d.day, default: DayAgg()].charged += d.chargedPercent
        }
        for s in screen { days[s.day, default: DayAgg()].screen += s.seconds }
        for (day, a) in days {
            bexec("""
                INSERT INTO battery_daily(day, consumed, charged, screen_s, max_cap, nominal, cycles, min_pct, max_pct, temp_sum, temp_n, temp_min, temp_max)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(day) DO UPDATE SET
                  consumed = consumed + excluded.consumed, charged = charged + excluded.charged, screen_s = screen_s + excluded.screen_s,
                  max_cap = COALESCE(excluded.max_cap, max_cap), nominal = COALESCE(excluded.nominal, nominal),
                  cycles = COALESCE(excluded.cycles, cycles),
                  min_pct = CASE WHEN excluded.min_pct IS NULL THEN min_pct WHEN min_pct IS NULL THEN excluded.min_pct ELSE MIN(min_pct, excluded.min_pct) END,
                  max_pct = CASE WHEN excluded.max_pct IS NULL THEN max_pct WHEN max_pct IS NULL THEN excluded.max_pct ELSE MAX(max_pct, excluded.max_pct) END,
                  temp_sum = temp_sum + excluded.temp_sum, temp_n = temp_n + excluded.temp_n,
                  temp_min = CASE WHEN excluded.temp_min IS NULL THEN temp_min WHEN temp_min IS NULL THEN excluded.temp_min ELSE MIN(temp_min, excluded.temp_min) END,
                  temp_max = CASE WHEN excluded.temp_max IS NULL THEN temp_max WHEN temp_max IS NULL THEN excluded.temp_max ELSE MAX(temp_max, excluded.temp_max) END
                """, [.text(day), .real(a.consumed), .real(a.charged), .int(a.screen), Self.opt(a.maxCap), Self.opt(a.nominal),
                      Self.opt(a.cycles), Self.opt(a.minPct), Self.opt(a.maxPct), .int(a.tempSum), .int(a.tempN),
                      Self.opt(a.tempMin), Self.opt(a.tempMax)])
        }
    }

    /// Dakikalık 14 gün, günlük 400 gün.
    func batteryMaintenance(now: Date = .now, calendar: Calendar = UsageStore.keyCalendar) {
        guard db != nil else { return }
        let minCut = Int(now.timeIntervalSince1970) - Self.batteryMinuteRetentionDays * 86_400
        let dayCut = calendar.date(byAdding: .day, value: -Self.batteryDailyRetentionDays, to: now) ?? now
        bexec("DELETE FROM battery_min WHERE ts < ?", [.int(minCut)])
        bexec("DELETE FROM battery_daily WHERE day < ?", [.text(Self.dayKey(dayCut, calendar: calendar))])
    }

    /// `bucket` saniyelik kovalara indirgenmiş seri (bucket ≤ 60 → ham dakikalık).
    func batterySamples(from: Date, to: Date = .now, bucketSeconds bucket: Int = 60) -> [BatterySample] {
        var out: [BatterySample] = []
        let b = max(60, bucket)
        run("""
            SELECT ts / ? * ?, CAST(ROUND(AVG(pct)) AS INTEGER), MAX(charging), MAX(plugged), AVG(temp_x10), AVG(mv), AVG(ma),
                   AVG(sys_mw), MAX(adapter_w), MAX(raw_max), MAX(nominal), MAX(cycles)
            FROM battery_min WHERE ts >= ? AND ts <= ? GROUP BY ts / ? ORDER BY 1
            """, [.int(b), .int(b), .int(Int(from.timeIntervalSince1970)), .int(Int(to.timeIntervalSince1970)), .int(b)]) { s in
            func o(_ c: Int32) -> Int? { sqlite3_column_type(s, c) == SQLITE_NULL ? nil : Int(sqlite3_column_double(s, c).rounded()) }
            out.append(BatterySample(ts: Int(sqlite3_column_int64(s, 0)), pct: Int(sqlite3_column_int64(s, 1)),
                                     charging: sqlite3_column_int64(s, 2) != 0, plugged: sqlite3_column_int64(s, 3) != 0,
                                     tempC: o(4).map { Double($0) / 10 }, voltageMV: o(5), amperageMA: o(6), systemMW: o(7),
                                     adapterW: o(8), rawMaxMAh: o(9), nominalMAh: o(10), cycles: o(11)))
        }
        return out
    }

    func batteryDaily(fromDay: String, toDay: String) -> [BatteryDayRow] {
        var out: [BatteryDayRow] = []
        run("""
            SELECT day, consumed, charged, screen_s, max_cap, nominal, cycles, min_pct, max_pct, temp_sum, temp_n, temp_min, temp_max
            FROM battery_daily WHERE day >= ? AND day <= ? ORDER BY day
            """, [.text(fromDay), .text(toDay)]) { s in
            func o(_ c: Int32) -> Int? { sqlite3_column_type(s, c) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s, c)) }
            let n = Int(sqlite3_column_int64(s, 10))
            out.append(BatteryDayRow(day: Self.text(s, 0), consumedPercent: sqlite3_column_double(s, 1),
                                     chargedPercent: sqlite3_column_double(s, 2), screenSeconds: Int(sqlite3_column_int64(s, 3)),
                                     maxCapacityMAh: o(4), nominalMAh: o(5), cycles: o(6), minPercent: o(7), maxPercent: o(8),
                                     avgTemp: n > 0 ? Double(sqlite3_column_int64(s, 9)) / Double(n) / 10 : nil,
                                     minTemp: o(11).map { Double($0) / 10 }, maxTemp: o(12).map { Double($0) / 10 }))
        }
        return out
    }

    /// Son %100 görülen an ("Son %100'e şarj: dün 10:36").
    func lastFullCharge() -> Date? {
        var ts: Int?
        run("SELECT MAX(ts) FROM battery_min WHERE pct >= 100", []) { s in
            if sqlite3_column_type(s, 0) != SQLITE_NULL { ts = Int(sqlite3_column_int64(s, 0)) }
        }
        return ts.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    func batteryRowCount() -> Int {
        var n = 0
        run("SELECT COUNT(*) FROM battery_min", []) { n = Int(sqlite3_column_int64($0, 0)) }
        return n
    }
}
