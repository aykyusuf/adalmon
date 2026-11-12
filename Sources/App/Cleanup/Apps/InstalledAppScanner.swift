import AppKit
import Darwin
import Foundation

/// Uygulamanın kendisi neden silinemiyor.
enum AppRemovalBlock: Sendable, Equatable {
    case appStore, rootOwned

    var note: String {
        switch self {
        case .appStore:
            "App Store uygulaması: Adalmon kaldıramaz. Finder'da gösterip oradan Çöp'e taşıyın (Finder parola isteyebilir)."
        case .rootOwned:
            "Bu uygulama yönetici (root) sahipli: Adalmon yönetici komutu çalıştırmaz. Finder'da gösterip oradan Çöp'e taşıyın (Finder parola isteyecek)."
        }
    }
}

struct InstalledApp: Identifiable, Sendable, Equatable {
    let path: String
    let dev: Int32
    let ino: UInt64
    let bundleID: String
    let name: String
    let names: Set<String>
    let version: String?
    let bytes: UInt64
    let isAppStore: Bool
    let ownerIsRoot: Bool
    var leftovers: [DeletionCandidate] = []

    var id: String { path }
    var identity: AppMatchKey { AppMatchKey(bundleID: bundleID, names: names) }
    var leftoverBytes: UInt64 { leftovers.reduce(0) { $0 + $1.bytes } }
    var removalBlock: AppRemovalBlock? { isAppStore ? .appStore : (ownerIsRoot ? .rootOwned : nil) }

    /// Uygulama paketi için silme adayı (`.appBundle` kapsamı; çalışıyorsa silme anında reddedilir).
    var bundleCandidate: DeletionCandidate {
        DeletionCandidate(path: path, dev: dev, ino: ino, bytes: bytes, kind: "apps.bundle", scope: .appBundle,
                          blockingBundleIDs: [bundleID], displayName: name)
    }
}

/// Taranacak uygulama klasörü. `subfolders`: bir düzey alt klasördeki `.app`'ler de aranır (yalnız /Applications).
struct AppRoot: Sendable, Equatable {
    var path: String
    var subfolders: Bool
}

struct AppScanOutput: Sendable, Equatable {
    var apps: [InstalledApp]
    var orphans: [OrphanGroup]
}

enum InstalledAppScanner {
    static func defaultRoots(home: String) -> [AppRoot] {
        [AppRoot(path: "/Applications", subfolders: true), AppRoot(path: home + "/Applications", subfolders: false)]
    }

    static let liveResolver: @Sendable (String) -> Bool = { id in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    static func ownIDs() -> [String] { [AdalmonIdentity.appBundleID] }

    /// Kurulu uygulamalar (artıksız). `com.apple.*`, Adalmon, /System altındakiler ve sembolik bağ olan `.app`'ler atlanır.
    static func scanBundles(roots: [AppRoot], ownIDs: [String] = ownIDs(), ownBundlePaths: [String] = [Bundle.main.bundlePath],
                            isCancelled: @escaping () -> Bool = { false }) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        for root in roots {
            if isCancelled() { break }
            guard let canonicalRoot = CleanupDeleter.realPath(root.path),
                  !CleanupDeleter.isUnderSystemTree(CleanupDeleter.components(canonicalRoot)) else { continue }
            for name in sortedEntries(root.path) {
                if isCancelled() { break }
                let path = root.path + "/" + name
                if name.hasSuffix(".app") {
                    if let app = readApp(at: path, ownIDs: ownIDs, ownBundlePaths: ownBundlePaths, isCancelled: isCancelled), seen.insert(app.path).inserted {
                        apps.append(app)
                    }
                } else if root.subfolders, isRealDirectory(path) {
                    for child in sortedEntries(path) where child.hasSuffix(".app") {
                        if isCancelled() { break }
                        if let app = readApp(at: path + "/" + child, ownIDs: ownIDs, ownBundlePaths: ownBundlePaths, isCancelled: isCancelled),
                           seen.insert(app.path).inserted {
                            apps.append(app)
                        }
                    }
                }
            }
        }
        return apps.sorted { $0.bytes > $1.bytes }
    }

    /// Tam tarama: uygulamalar + artıkları + yetimler. İptalde kısmi sonuç döner (çağıran atar).
    static func scan(home: String, roots: [AppRoot]? = nil, running: Set<String> = [], ownIDs: [String] = ownIDs(),
                     ownBundlePaths: [String] = [Bundle.main.bundlePath], resolver: @Sendable (String) -> Bool = liveResolver,
                     minOrphanFolderBytes: UInt64 = OrphanFinder.minFolderBytes, isCancelled: @escaping () -> Bool = { false },
                     progress: (Int, Int) -> Void = { _, _ in }) -> AppScanOutput {
        var apps = scanBundles(roots: roots ?? defaultRoots(home: home), ownIDs: ownIDs, ownBundlePaths: ownBundlePaths, isCancelled: isCancelled)
        let index = LibraryIndex.load(home: home)
        let ids = Set(apps.map(\.bundleID))
        for i in apps.indices {
            if isCancelled() { break }
            progress(i, apps.count)
            // Aynı kimliğin ikinci kopyası (başka klasörde) "başka uygulama" sayılmaz; farklı kimlikli uygulamaların adları sayılır.
            let own = apps[i].bundleID
            let otherNames = apps.filter { $0.bundleID != own }.reduce(into: Set<String>()) { $0.formUnion($1.names) }
            apps[i].leftovers = LeftoverRules.leftovers(for: apps[i].identity, index: index, otherIDs: ids, otherNames: otherNames,
                                                        isCancelled: isCancelled)
        }
        let orphans = isCancelled() ? [] : OrphanFinder.find(index: index, installedIDs: ids.union(running), ownIDs: ownIDs, resolver: resolver,
                                                             minFolderBytes: minOrphanFolderBytes, isCancelled: isCancelled)
        return AppScanOutput(apps: apps, orphans: orphans)
    }

    // MARK: Yardımcılar

    private static func sortedEntries(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
    }

    private static func isRealDirectory(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    private static func readApp(at path: String, ownIDs: [String], ownBundlePaths: [String], isCancelled: @escaping () -> Bool) -> InstalledApp? {
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return nil } // sembolik bağ .app atlanır
        let canonical = CleanupDeleter.realPath(path) ?? path
        if ownBundlePaths.contains(where: { CleanupDeleter.realPath($0) == canonical }) { return nil }
        guard let plist = NSDictionary(contentsOfFile: path + "/Contents/Info.plist"),
              let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty,
              !LeftoverRules.isProtectedID(bundleID, ownIDs: ownIDs) else { return nil }
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var names: Set<String> = [fileName]
        for key in ["CFBundleName", "CFBundleDisplayName"] {
            if let value = plist[key] as? String, !value.isEmpty { names.insert(value) }
        }
        let display = (plist["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fileName
        let version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
        let bytes = FolderScanner.scan(root: FolderScanRoot(path: path, maxDepth: 0), isCancelled: isCancelled)?.totalBytes ?? 0
        return InstalledApp(path: path, dev: st.st_dev, ino: st.st_ino, bundleID: bundleID, name: display, names: names, version: version,
                            bytes: bytes, isAppStore: FileManager.default.fileExists(atPath: path + "/Contents/_MASReceipt"),
                            ownerIsRoot: st.st_uid == 0)
    }
}
