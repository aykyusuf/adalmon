import Foundation

/// Günlükteki tek satır. Eski satırlarda `mode` yoktur (hepsi Çöp'e taşımaydı) ve `kind` yerine `category` vardır.
struct CleanupLogEntry: Sendable, Equatable, Identifiable {
    let id: Int
    let date: Date?
    /// Tür kimliği (`kind`); eski satırlarda kategori adı.
    let kind: String
    let path: String
    let bytes: UInt64
    let mode: DeleteMode
    let trashedTo: String?
    /// "moved" (Çöp'e taşındı), "deleted" (kalıcı silindi) ya da "skipped".
    let result: String
    let reason: String?

    var isDone: Bool { result == "moved" || result == "deleted" }
}

/// `Cleanup-log.jsonl`: işlem başına öğe başına bir satır, en çok 500 satır tutulur.
enum CleanupAuditLog {
    static let limit = 500
    static var defaultURL: URL { AppEnvironment.supportDirectory.appending(path: "Cleanup-log.jsonl") }

    static func append(_ results: [CleanupResult], mode: DeleteMode, url: URL, now: Date = Date()) {
        guard !results.isEmpty else { return }
        let stamp = ISO8601DateFormatter().string(from: now)
        var lines: [String] = []
        for r in results {
            var obj: [String: Any] = [
                "date": stamp, "kind": r.candidate.kind.rawValue, "path": r.candidate.path,
                "bytes": r.candidate.bytes, "mode": mode.rawValue, "trashedTo": NSNull(),
            ]
            switch r.outcome {
            case .trashed(let to):
                obj["result"] = "moved"
                obj["trashedTo"] = to?.path ?? NSNull()
            case .deleted:
                obj["result"] = "deleted"
            case .skipped(let refusal):
                obj["result"] = "skipped"
                obj["reason"] = String(describing: refusal)
            case .failed(let message):
                obj["result"] = "skipped"
                obj["reason"] = message
            }
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]),
               let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
        let existing = (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        let kept = (existing + lines).suffix(limit)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data((kept.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }

    /// Son `limit` satır (en yeni önce). `mode` yoksa `.trash`, `kind` yoksa `category` okunur.
    static func read(url: URL = defaultURL, limit: Int = 20) -> [CleanupLogEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let iso = ISO8601DateFormatter()
        let lines = text.split(separator: "\n").suffix(limit)
        var out: [CleanupLogEntry] = []
        for (i, line) in lines.enumerated().reversed() {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            out.append(CleanupLogEntry(
                id: i, date: (obj["date"] as? String).flatMap(iso.date(from:)),
                kind: obj["kind"] as? String ?? obj["category"] as? String ?? "",
                path: obj["path"] as? String ?? "", bytes: (obj["bytes"] as? NSNumber)?.uint64Value ?? 0,
                mode: (obj["mode"] as? String).flatMap(DeleteMode.init(rawValue:)) ?? .trash,
                trashedTo: obj["trashedTo"] as? String, result: obj["result"] as? String ?? "", reason: obj["reason"] as? String
            ))
        }
        return out
    }
}
