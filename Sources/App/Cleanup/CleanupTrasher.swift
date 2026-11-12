import Darwin
import Foundation

struct CleanupResult: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        case moved(trashedTo: URL?)
        case skipped(CleanupTrasher.Refusal)
        case failed(String)
    }

    let item: CleanupItem
    let outcome: Outcome

    var isMoved: Bool { if case .moved = outcome { true } else { false } }

    var reasonText: String? {
        switch outcome {
        case .moved: nil
        case .skipped(let r): r.message
        case .failed(let message): message
        }
    }
}

struct CleanupLogEntry: Sendable, Equatable, Identifiable {
    let id: Int
    let date: Date?
    let category: String
    let path: String
    let bytes: UInt64
    let trashedTo: String?
    let result: String
    let reason: String?
}

/// Tek taşıma noktası: her öğe taşınmadan hemen önce yeniden doğrulanır, yalnızca Çöp Sepeti'ne taşınır (kalıcı silme yok),
/// her öğe günlüğe bir satır yazar.
struct CleanupTrasher: Sendable {
    enum Refusal: Error, Equatable, Sendable {
        case notAbsolute, symlink, missing, changed, notUnderAllowedRoot, isRoot, notDirectChild, nameNotAllowed, protectedPath, appRunning

        var message: String {
            switch self {
            case .notAbsolute: "Geçersiz yol"
            case .symlink: "Sembolik bağ"
            case .missing: "Artık yok"
            case .changed: "Taramadan sonra değişmiş"
            case .notUnderAllowedRoot: "İzinli klasörde değil"
            case .isRoot: "Kök klasörün kendisi"
            case .notDirectChild: "Doğrudan alt öğe değil"
            case .nameNotAllowed: "Korunan ad"
            case .protectedPath: "Korunan konum"
            case .appRunning: "Uygulama açık"
            }
        }
    }

    static let logLimit = 500
    static var defaultLogURL: URL { AppEnvironment.supportDirectory.appending(path: "Cleanup-log.jsonl") }
    static let systemTrash: @Sendable (URL) throws -> URL? = { url in
        var out: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &out)
        return out as URL?
    }

    var roots: [CleanupRoot]
    var home: String
    var runningBundleIDs: Set<String>
    var logURL: URL = CleanupTrasher.defaultLogURL
    var moveToTrash: @Sendable (URL) throws -> URL? = CleanupTrasher.systemTrash

    // MARK: Doğrulama

    func validate(_ item: CleanupItem) -> Refusal? {
        let path = item.path
        // 1. Mutlak, temiz yol.
        guard path.hasPrefix("/"), path.count > 1 else { return .notAbsolute }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        if parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) { return .notAbsolute }
        // 2-4. Var, sembolik bağ değil, taramadaki nesneyle aynı.
        var st = stat()
        guard lstat(path, &st) == 0 else { return .missing }
        if (st.st_mode & S_IFMT) == S_IFLNK { return .symlink }
        guard st.st_dev == item.dev, st.st_ino == item.ino else { return .changed }
        // 5. Kanonik yol.
        let name = (path as NSString).lastPathComponent
        guard let parent = Self.realPath((path as NSString).deletingLastPathComponent),
              let canonHome = Self.realPath(home) else { return .notUnderAllowedRoot }
        let canonical = Self.components(parent) + [name]
        let homeParts = Self.components(canonHome)
        // 6. Ebeveyn, kategorinin izinli bir köküne eşit olmalı (bileşen bileşen).
        guard item.category != .trash else { return .notUnderAllowedRoot }
        var matched: CleanupRoot?
        var sawRoot = false, sawDeeper = false
        for root in roots where root.category == item.category {
            guard let canonRoot = Self.realPath(root.path) else { continue }
            let rootParts = Self.components(canonRoot)
            guard Self.isStrictDescendant(rootParts, of: homeParts) else { continue }
            if canonical == rootParts { sawRoot = true }
            else if Array(canonical.dropLast()) == rootParts { matched = root; break }
            else if Self.isStrictDescendant(canonical, of: rootParts) { sawDeeper = true }
        }
        guard let root = matched else {
            if sawRoot { return .isRoot }
            if sawDeeper { return .notDirectChild }
            return .notUnderAllowedRoot
        }
        // 7. Ad kuralları yeniden.
        guard root.allows(name) else { return .nameNotAllowed }
        // 8. Sert yasak listesi: bunlardan birine eşit ya da atası olan yol.
        for protected in Self.protectedPaths(homeParts: homeParts) where canonical == protected || Self.isStrictDescendant(protected, of: canonical) {
            return .protectedPath
        }
        // 9. Çalışan uygulama.
        if CleanupCatalog.blockedReason(category: item.category, name: name, runningBundleIDs: runningBundleIDs) != nil { return .appRunning }
        return nil
    }

    // MARK: Taşıma

    /// Her öğeyi doğrular, geçerse Çöp Sepeti'ne taşır ve günlüğe yazar. Hata fırlatmaz; sonuçları toplar.
    func trash(_ items: [CleanupItem]) -> [CleanupResult] {
        var results: [CleanupResult] = []
        for item in items {
            if let refusal = validate(item) {
                results.append(CleanupResult(item: item, outcome: .skipped(refusal)))
                continue
            }
            do {
                let to = try moveToTrash(URL(fileURLWithPath: item.path))
                results.append(CleanupResult(item: item, outcome: .moved(trashedTo: to)))
            } catch {
                results.append(CleanupResult(item: item, outcome: .failed((error as NSError).localizedDescription)))
            }
        }
        appendLog(results)
        return results
    }

    // MARK: Günlük

    private func appendLog(_ results: [CleanupResult]) {
        guard !results.isEmpty else { return }
        let iso = ISO8601DateFormatter()
        let now = iso.string(from: Date())
        var lines: [String] = []
        for r in results {
            var obj: [String: Any] = ["date": now, "category": r.item.category.rawValue, "path": r.item.path, "bytes": r.item.bytes]
            switch r.outcome {
            case .moved(let to):
                obj["result"] = "moved"
                obj["trashedTo"] = to?.path ?? NSNull()
            case .skipped(let refusal):
                obj["result"] = "skipped"
                obj["trashedTo"] = NSNull()
                obj["reason"] = String(describing: refusal)
            case .failed(let message):
                obj["result"] = "skipped"
                obj["trashedTo"] = NSNull()
                obj["reason"] = message
            }
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]),
               let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
        let existing = (try? String(contentsOf: logURL, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        let kept = (existing + lines).suffix(Self.logLimit)
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data((kept.joined(separator: "\n") + "\n").utf8).write(to: logURL, options: .atomic)
    }

    /// Son `limit` günlük satırı (en yeni önce).
    static func readLog(url: URL = defaultLogURL, limit: Int = 20) -> [CleanupLogEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let iso = ISO8601DateFormatter()
        let lines = text.split(separator: "\n").suffix(limit)
        var out: [CleanupLogEntry] = []
        for (i, line) in lines.enumerated().reversed() {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            out.append(CleanupLogEntry(
                id: i, date: (obj["date"] as? String).flatMap(iso.date(from:)), category: obj["category"] as? String ?? "",
                path: obj["path"] as? String ?? "", bytes: (obj["bytes"] as? NSNumber)?.uint64Value ?? 0,
                trashedTo: obj["trashedTo"] as? String, result: obj["result"] as? String ?? "", reason: obj["reason"] as? String
            ))
        }
        return out
    }

    // MARK: Yol yardımcıları

    static func realPath(_ path: String) -> String? {
        guard let p = Darwin.realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }

    static func components(_ path: String) -> [String] {
        URL(fileURLWithPath: path).standardizedFileURL.pathComponents
    }

    /// `path`, `ancestor`ın kesin alt yolu mu (bileşen bileşen; "Caches2" "Caches"in altı sayılmaz).
    static func isStrictDescendant(_ path: [String], of ancestor: [String]) -> Bool {
        path.count > ancestor.count && Array(path.prefix(ancestor.count)) == ancestor
    }

    static func protectedPaths(homeParts: [String]) -> [[String]] {
        let system = ["/", "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/private", "/Volumes"].map(components)
        let homeRelative = [
            "", "Library", "Library/Caches", "Library/Application Support", "Library/Developer",
            "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music",
            "Library/Mobile Documents", "Library/Containers", "Library/Group Containers", ".Trash",
        ]
        return system + homeRelative.map { rel in homeParts + rel.split(separator: "/").map(String.init) }
    }
}
