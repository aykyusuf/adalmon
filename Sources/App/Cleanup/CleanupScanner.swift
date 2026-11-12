import Darwin
import Foundation

/// Temizlik taraması: yalnızca istek üzerine, izinli köklerin doğrudan çocuklarını boyutlarıyla listeler.
/// Klasör boyutu için `FolderScanner` (kök başına tek geçiş) kullanılır; sembolik bağlar her zaman atlanır.
enum CleanupScanner {
    enum Probe: Equatable { case ok, missing, noAccess(AccessReason) }

    struct Output: Sendable {
        var items: [CleanupItem] = []
        /// Kök yolu → durum.
        var states: [String: CleanupRootState] = [:]
    }

    /// Kökü açmayı dener: TCC reddi `FolderScanner`da 0 baytlık sonuç verdiği için önce ayırt edilir.
    /// Ret durumunda nedeni (`CleanupAccess.reason`) da döner. `using` testlerde sahte deneme içindir.
    static func probe(_ path: String, home: String = NSHomeDirectory(), using probe: PathProbe = .live) -> Probe {
        switch probe.check(path) {
        case .ok: .ok
        case .missing: .missing
        case .denied: .noAccess(CleanupAccess.reason(for: path, home: home))
        }
    }

    /// - Parameter projectRoots: `.projectArtifacts` için kullanıcının seçtiği proje klasörleri (katalog kökü değildir).
    static func scan(categories: [CleanupCategory], home: String, runningBundleIDs: Set<String>,
                     ownBundleID: String? = Bundle.main.bundleIdentifier, now: Date = Date(),
                     projectRoots: [String] = [], probe pathProbe: PathProbe = .live,
                     isCancelled: @escaping () -> Bool = { false }, progress: (CleanupCategory) -> Void = { _ in }) -> Output {
        var out = Output()
        let wanted = Set(categories)
        var lastCategory: CleanupCategory?
        for root in CleanupCatalog.roots(home: home, ownBundleID: ownBundleID) where wanted.contains(root.category) {
            if isCancelled() { break }
            if root.category != lastCategory {
                lastCategory = root.category
                progress(root.category)
            }
            switch probe(root.path, home: home, using: pathProbe) {
            case .missing: out.states[root.path] = .missing
            case .noAccess: out.states[root.path] = .noAccess
            case .ok:
                guard let items = scanRoot(root, runningBundleIDs: runningBundleIDs, now: now, isCancelled: isCancelled) else {
                    out.states[root.path] = .noAccess
                    continue
                }
                out.states[root.path] = .scanned
                out.items += items
            }
        }
        if wanted.contains(.projectArtifacts), !isCancelled() {
            progress(.projectArtifacts)
            scanProjects(projectRoots, home: home, runningBundleIDs: runningBundleIDs, probe: pathProbe, isCancelled: isCancelled, into: &out)
        }
        return out
    }

    /// Proje klasörleri: kök başına durum; sembolik bağ olan kök `.missing` olur (O_NOFOLLOW), iç içe kökler aynı yolu iki kez listelemez.
    private static func scanProjects(_ roots: [String], home: String, runningBundleIDs: Set<String>, probe pathProbe: PathProbe,
                                     isCancelled: @escaping () -> Bool, into out: inout Output) {
        var seen = Set<String>()
        for root in roots {
            if isCancelled() { break }
            switch probe(root, home: home, using: pathProbe) {
            case .missing: out.states[root] = .missing
            case .noAccess: out.states[root] = .noAccess
            case .ok:
                guard let items = ProjectArtifactScanner.scan(root: root, runningBundleIDs: runningBundleIDs, isCancelled: isCancelled) else {
                    out.states[root] = .missing
                    continue
                }
                out.states[root] = .scanned
                out.items += items.filter { seen.insert($0.path).inserted }
            }
        }
    }

    /// Çöp Sepeti'nin toplam boyutu (öğe listelenmez, işlem yapılmaz).
    static func trashSize(home: String, isCancelled: @escaping () -> Bool = { false }) -> (state: CleanupRootState, bytes: UInt64) {
        let path = CleanupCatalog.trashPath(home: home)
        switch probe(path) {
        case .missing: return (.missing, 0)
        case .noAccess: return (.noAccess, 0)
        case .ok:
            let result = FolderScanner.scan(root: FolderScanRoot(path: path, maxDepth: 0), minRecordedBytes: .max, isCancelled: isCancelled)
            guard let result else { return (.missing, 0) }
            return (.scanned, result.totalBytes)
        }
    }

    /// Kökün doğrudan çocukları. Listeleme başarısızsa nil (erişim yok).
    private static func scanRoot(_ root: CleanupRoot, runningBundleIDs: Set<String>, now: Date, isCancelled: @escaping () -> Bool) -> [CleanupItem]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return nil }
        let isDownloads = root.category == .downloads
        let candidates = names.sorted().filter { root.allows($0) && !(isDownloads && $0.hasPrefix(".")) }
        guard !candidates.isEmpty else { return [] }

        // Klasör boyutları: tek geçiş (onlyNames varsa yalnızca o çocuklar ayrı ayrı).
        var dirBytes: [String: UInt64] = [:]
        if root.onlyNames == nil {
            let scanRoot = FolderScanRoot(path: root.path, maxDepth: 1, skipChildNames: root.skipNames, skipChildPrefixes: root.skipPrefixes)
            let result = FolderScanner.scan(root: scanRoot, minRecordedBytes: CleanupCatalog.minItemBytes, isCancelled: isCancelled)
            for entry in result?.entries ?? [] where entry.depth == 1 { dirBytes[entry.path] = entry.bytes }
        } else {
            for name in candidates {
                if isCancelled() { break }
                let child = root.path + "/" + name
                if let r = FolderScanner.scan(root: FolderScanRoot(path: child, maxDepth: 0), minRecordedBytes: .max, isCancelled: isCancelled) {
                    dirBytes[child] = r.totalBytes
                }
            }
        }
        if isCancelled() { return [] }

        let staleBefore = now.addingTimeInterval(-Double(CleanupCatalog.downloadsStaleDays) * 86_400)
        var items: [CleanupItem] = []
        for name in candidates {
            let child = root.path + "/" + name
            var st = stat()
            guard lstat(child, &st) == 0 else { continue }
            let type = st.st_mode & S_IFMT
            let bytes: UInt64
            switch type {
            case S_IFDIR:
                guard let b = dirBytes[child] else { continue } // 1 MB altı, atlanan ya da başka birim
                bytes = b
            case S_IFREG:
                bytes = UInt64(max(0, st.st_blocks)) * 512
            default:
                continue // sembolik bağ ve diğerleri
            }
            guard bytes >= CleanupCatalog.minItemBytes else { continue }
            let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            if isDownloads, bytes < CleanupCatalog.downloadsLargeBytes, modified >= staleBefore { continue }
            items.append(CleanupItem(
                path: child, rootPath: root.path, category: root.category, bytes: bytes, isDirectory: type == S_IFDIR,
                modified: modified, dev: st.st_dev, ino: st.st_ino,
                blockedReason: CleanupCatalog.blockedReason(category: root.category, name: name, runningBundleIDs: runningBundleIDs)
                    ?? (root.blockingBundleIDs.isDisjoint(with: runningBundleIDs) ? nil : CleanupCatalog.runningBadge),
                blockingBundleIDs: root.blockingBundleIDs
            ))
        }
        return items.sorted { $0.bytes > $1.bytes }
    }
}
