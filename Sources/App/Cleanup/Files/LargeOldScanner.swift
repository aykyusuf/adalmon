import Foundation

/// "Büyük & eski" listesindeki bir dosya. `bytes`, diskte ayrılan boyuttur (`st_blocks`).
struct LargeOldItem: Identifiable, Sendable, Equatable {
    var id: String { path }
    let path: String
    let dev: Int32
    let ino: UInt64
    let bytes: UInt64
    let modified: Date

    var name: String { (path as NSString).lastPathComponent }

    /// Silme adayı: `.descendant` kapsamı, kökler kullanıcının seçtiği klasörler (dosya adı kısıtı yok).
    func candidate(roots: [String]) -> DeletionCandidate {
        DeletionCandidate(path: path, dev: dev, ino: ino, bytes: bytes, kind: LargeOldScanner.kind,
                          scope: .descendant(roots: roots, nameAllowlist: nil), displayName: name)
    }
}

struct LargeOldResult: Sendable, Equatable {
    var items: [LargeOldItem] = []
    var rootStates: [String: CleanupRootState] = [:]
    var unreadableDirs = 0
    var filesSeen = 0
    var cancelled = false
}

struct LargeOldScanner: Sendable {
    static let kind: CleanupKind = "files.largeOld"
    static let defaultMinBytes: UInt64 = 100 << 20
    static let defaultOldDays = 365

    var minBytes: UInt64 = defaultMinBytes
    var stat: StatProvider = .live
    var skipPaths: Set<String> = []

    /// Köklerdeki `minBytes` ve üstü dosyaları en büyükten küçüğe verir. Yaş süzgeci taramadan sonra uygulanır (`filter`).
    func scan(roots: [String], isCancelled: @escaping () -> Bool = { false },
              progress: @escaping (FileWalker.Progress) -> Void = { _ in }) -> LargeOldResult {
        var found: [LargeOldItem] = []
        let threshold = minBytes
        let walker = FileWalker(stat: stat, skipPaths: skipPaths)
        let outcome = walker.walk(roots: roots, isCancelled: isCancelled, progress: progress) { path, st in
            guard st.allocated >= threshold else { return }
            found.append(LargeOldItem(path: path, dev: st.dev, ino: st.ino, bytes: st.allocated, modified: st.mtime))
        }
        found.sort { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path }
        return LargeOldResult(items: found, rootStates: outcome.rootStates, unreadableDirs: outcome.unreadableDirs,
                              filesSeen: outcome.filesSeen, cancelled: outcome.cancelled)
    }

    static func isOld(_ item: LargeOldItem, olderThanDays days: Int, now: Date = Date()) -> Bool {
        item.modified <= now.addingTimeInterval(-TimeInterval(days) * 86_400)
    }

    /// `onlyOld` açıksa yalnızca `days` günden eski olanlar.
    static func filter(_ items: [LargeOldItem], onlyOld: Bool, olderThanDays days: Int, now: Date = Date()) -> [LargeOldItem] {
        onlyOld ? items.filter { isOld($0, olderThanDays: days, now: now) } : items
    }
}
