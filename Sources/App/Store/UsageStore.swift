import Foundation
import SQLite3

/// Günlük kullanım kaydı (SQLite). Tüm erişim bu actor üzerinden.
actor UsageStore {
    struct Row: Sendable {
        var app: String
        var host: String
        var mobile: Bool
        var bytesIn: UInt64
        var bytesOut: UInt64
    }

    private var db: OpaquePointer?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Adalmon", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appending(path: "usage.sqlite").path
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
            ] { sqlite3_exec(handle, sql, nil, nil, nil) }
        }
    }

    static func dayKey(_ date: Date = .now) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    func add(day: String, rows: [Row]) {
        guard let db, !rows.isEmpty else { return }
        let sql = """
        INSERT INTO usage(day, app, host, mobile, bytes_in, bytes_out) VALUES(?,?,?,?,?,?)
        ON CONFLICT(day, app, host, mobile) DO UPDATE SET
          bytes_in = bytes_in + excluded.bytes_in, bytes_out = bytes_out + excluded.bytes_out
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
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
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
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

    func rows(day: String) -> [Row] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT app, host, mobile, bytes_in, bytes_out FROM usage WHERE day = ?", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
        var out: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Row(app: String(cString: sqlite3_column_text(stmt, 0)),
                           host: String(cString: sqlite3_column_text(stmt, 1)),
                           mobile: sqlite3_column_int(stmt, 2) != 0,
                           bytesIn: UInt64(max(0, sqlite3_column_int64(stmt, 3))),
                           bytesOut: UInt64(max(0, sqlite3_column_int64(stmt, 4)))))
        }
        return out
    }

    func interfaceBytes(day: String, mobile: Bool) -> UInt64 {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT bytes FROM iface_daily WHERE day = ? AND mobile = ?", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, mobile ? 1 : 0)
        return sqlite3_step(stmt) == SQLITE_ROW ? UInt64(max(0, sqlite3_column_int64(stmt, 0))) : 0
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
