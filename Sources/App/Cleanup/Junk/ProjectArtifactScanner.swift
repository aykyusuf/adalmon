import Darwin
import Foundation

/// Kullanıcının seçtiği proje klasörlerinde yeniden üretilebilir artıkları (node_modules, .build, DerivedData, target, Pods, build) bulur.
/// Kurallar: derinlik ≤ 6, sembolik bağ yok (kök dahil), bulunan artığın içine inilmez (iç içe olanda yalnızca dıştaki listelenir),
/// gizli klasörler (`.build` hariç) gezilmez. Boyut `FolderScanner` ile ölçülür. Hiçbir şey silinmez: yalnızca aday listeler.
enum ProjectArtifactScanner {
    /// `.descendant` kapsamı için ad izin listesi.
    static var artifactNames: Set<String> { DevRules.artifactNames }

    /// Silme kapsamı: yalnızca seçilen kökün altındaki, izin listesindeki adlar.
    static func scope(root: String) -> DeletionScope {
        .descendant(roots: [root], nameAllowlist: artifactNames)
    }

    /// Kök gerçek (sembolik bağ olmayan) bir klasör mü.
    static func isRealDirectory(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// - Parameters:
    ///   - skipPackages: true ise .app/.photoslibrary gibi paketlerin içine inilmez (varsayılan false: eski davranış).
    ///   - minBytes: bundan küçük artıklar listelenmez.
    ///   - runningBundleIDs: DerivedData/.build için Xcode açıksa öğe engelli işaretlenir.
    /// - Returns: kök sembolik bağ ya da klasör değilse nil.
    static func scan(root: String, runningBundleIDs: Set<String> = [], minBytes: UInt64 = CleanupCatalog.minItemBytes,
                     maxDepth: Int = DevRules.maxProjectDepth, skipPackages: Bool = false,
                     isCancelled: @escaping () -> Bool = { false }) -> [CleanupItem]? {
        guard isRealDirectory(root) else { return nil }
        var found: [String] = []
        walk(root, depth: 0, maxDepth: maxDepth, skipPackages: skipPackages, found: &found, isCancelled: isCancelled)

        var items: [CleanupItem] = []
        for path in found {
            if isCancelled() { break }
            var st = stat()
            guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { continue }
            guard let size = FolderScanner.scan(root: FolderScanRoot(path: path, maxDepth: 0), minRecordedBytes: .max, isCancelled: isCancelled),
                  size.totalBytes >= minBytes else { continue }
            let name = (path as NSString).lastPathComponent
            let blocking: Set<String> = name == "DerivedData" ? [CleanupCatalog.xcodeBundleID] : []
            items.append(CleanupItem(
                path: path, rootPath: root, category: .projectArtifacts, bytes: size.totalBytes, isDirectory: true,
                modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)), dev: st.st_dev, ino: st.st_ino,
                blockedReason: blocking.isDisjoint(with: runningBundleIDs) ? nil : CleanupCatalog.runningBadge,
                blockingBundleIDs: blocking
            ))
        }
        return items.sorted { $0.bytes > $1.bytes }
    }

    /// `dir` (derinlik `depth`) içindeki alt klasörleri gezer; çocukların derinliği `depth + 1`.
    private static func walk(_ dir: String, depth: Int, maxDepth: Int, skipPackages: Bool, found: inout [String], isCancelled: () -> Bool) {
        if isCancelled() { return }
        guard let kids = children(of: dir) else { return }
        let siblings = Set(kids.map(\.name))
        for kid in kids.sorted(by: { $0.name < $1.name }) where kid.isDirectory {
            if isCancelled() { return }
            let path = dir + "/" + kid.name
            if let rule = DevRules.rule(named: kid.name), rule.matches(siblings: siblings) {
                found.append(path) // artığın içine inilmez
                continue
            }
            if kid.name.hasPrefix(".") { continue }
            // Paket gibi davranan klasörlerin (.app, .photoslibrary…) içinde proje aranmaz (yalnızca isteyen çağıran için).
            if skipPackages, FileWalker.isPackage(kid.name) { continue }
            if depth + 1 < maxDepth { walk(path, depth: depth + 1, maxDepth: maxDepth, skipPackages: skipPackages, found: &found, isCancelled: isCancelled) }
        }
    }

    private struct Child { let name: String; let isDirectory: Bool }

    /// Çocukların adı ve klasör olup olmadığı. Sembolik bağlar (d_type == DT_LNK) klasör sayılmaz; liste okunamazsa nil.
    private static func children(of path: String) -> [Child]? {
        guard let dir = opendir(path) else { return nil }
        defer { closedir(dir) }
        var out: [Child] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            var isDir = entry.pointee.d_type == UInt8(DT_DIR)
            if entry.pointee.d_type == UInt8(DT_UNKNOWN) {
                var st = stat()
                isDir = lstat(path + "/" + name, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
            }
            out.append(Child(name: name, isDirectory: isDir))
        }
        return out
    }
}

/// Kullanıcının seçtiği proje klasörlerinin listesi (kendi küçük deposu; `Preferences`e dokunmaz).
struct ProjectFoldersStore {
    static let defaultsKey = "cleanupProjectFolders"

    enum AddError: Error, Equatable, Sendable {
        case notDirectory, symlink, notAllowed, alreadyAdded

        var message: String {
            switch self {
            case .notDirectory: "Klasör bulunamadı."
            case .symlink: "Sembolik bağ seçilemez; gerçek klasörü seçin."
            case .notAllowed: "Bu klasör seçilemez: ev klasörünün kendisi, Library ve sistem klasörleri taranmaz."
            case .alreadyAdded: "Bu klasör zaten listede."
            }
        }
    }

    let defaults: UserDefaults
    let home: String

    init(defaults: UserDefaults = .standard, home: String = NSHomeDirectory()) {
        self.defaults = defaults
        self.home = home
    }

    var folders: [String] { (defaults.stringArray(forKey: Self.defaultsKey) ?? []).filter { $0.hasPrefix("/") } }

    /// Ev klasörünün altındaki (Library ve ev klasörünün kendisi hariç) ya da harici birimdeki gerçek klasörler.
    func validate(_ path: String) -> AddError? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return .notDirectory }
        if (st.st_mode & S_IFMT) == S_IFLNK { return .symlink }
        guard (st.st_mode & S_IFMT) == S_IFDIR else { return .notDirectory }
        guard let real = CleanupDeleter.realPath(path), let realHome = CleanupDeleter.realPath(home) else { return .notAllowed }
        let parts = CleanupDeleter.components(real)
        let homeParts = CleanupDeleter.components(realHome)
        if parts == homeParts { return .notAllowed }
        let library = homeParts + ["Library"]
        if parts == library || CleanupDeleter.isStrictDescendant(parts, of: library) { return .notAllowed }
        if CleanupDeleter.isUnderSystemTree(parts) { return .notAllowed }
        guard CleanupDeleter.isAllowedDescendantRoot(parts, homeParts: homeParts) else { return .notAllowed }
        if folders.contains(real) { return .alreadyAdded }
        return nil
    }

    /// Ekler (gerçek yolla); reddedilirse neden döner.
    @discardableResult
    func add(_ path: String) -> AddError? {
        if let error = validate(path) { return error }
        guard let real = CleanupDeleter.realPath(path) else { return .notAllowed }
        defaults.set(folders + [real], forKey: Self.defaultsKey)
        return nil
    }

    func remove(_ path: String) {
        defaults.set(folders.filter { $0 != path }, forKey: Self.defaultsKey)
    }
}
