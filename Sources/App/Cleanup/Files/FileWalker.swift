import Darwin
import Foundation

/// Bir dosyanın `lstat` özeti. Boyut `st_blocks`tan (diskte ayrılan) gelir; mantıksal boyut yinelenen dosya eşlemesi içindir.
struct FileStat: Sendable, Equatable {
    var mode: mode_t
    var dev: Int32
    var ino: UInt64
    var nlink: UInt16
    var size: UInt64
    var allocated: UInt64
    var mtime: Date
    var flags: UInt32

    /// `SF_DATALESS` (sys/stat.h): içeriği iCloud'da, diskte olmayan dosya. Okumak indirmeyi tetikler; bu yüzden atlanır.
    static let datalessFlag: UInt32 = 0x4000_0000

    var isRegular: Bool { (mode & S_IFMT) == S_IFREG }
    var isDirectory: Bool { (mode & S_IFMT) == S_IFDIR }
    var isSymlink: Bool { (mode & S_IFMT) == S_IFLNK }
    var isDataless: Bool { flags & Self.datalessFlag != 0 }

    init(mode: mode_t, dev: Int32, ino: UInt64, nlink: UInt16 = 1, size: UInt64, allocated: UInt64, mtime: Date, flags: UInt32 = 0) {
        self.mode = mode
        self.dev = dev
        self.ino = ino
        self.nlink = nlink
        self.size = size
        self.allocated = allocated
        self.mtime = mtime
        self.flags = flags
    }

    init(_ st: stat) {
        self.init(
            mode: st.st_mode, dev: st.st_dev, ino: st.st_ino, nlink: st.st_nlink,
            size: UInt64(max(0, st.st_size)), allocated: UInt64(max(0, st.st_blocks)) * 512,
            mtime: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)), flags: st.st_flags
        )
    }
}

/// `lstat` sağlayıcısı (sembolik bağı izlemez). Testlerde bayrakları değiştiren bir sarmalayıcı verilir.
struct StatProvider: Sendable {
    var lstat: @Sendable (String) -> FileStat?

    static let live = StatProvider { path in
        var st = stat()
        guard Darwin.lstat(path, &st) == 0 else { return nil }
        return FileStat(st)
    }
}

/// Seçilen köklerde dosyaları dolaşır: sembolik bağ izlenmez, paket içleri ve iCloud'da duran (dataless) dosyalar atlanır,
/// sabit bağlar bir kez görülür, başka birime geçilmez. Her girdi arasında iptal denetlenir.
struct FileWalker {
    struct Progress: Sendable, Equatable {
        var files: Int
        var directory: String
    }

    struct Outcome: Sendable, Equatable {
        var rootStates: [String: CleanupRootState] = [:]
        var unreadableDirs = 0
        var filesSeen = 0
        var cancelled = false
    }

    /// Bu uzantılı klasörlerin içine girilmez (kütüphane paketleri ve uygulamalar).
    static let packageExtensions: Set<String> = ["app", "photoslibrary", "musiclibrary", "fcpbundle", "imovielibrary", "tvlibrary"]

    static func isPackage(_ name: String) -> Bool {
        if name == ".git" { return true }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return packageExtensions.contains(name[name.index(after: dot)...].lowercased())
    }

    /// Ev klasörü kök seçilirse içine girilmeyen yerler.
    static func defaultSkipPaths(home: String) -> Set<String> { [home + "/Library", home + "/.Trash"] }

    var stat: StatProvider = .live
    var skipPaths: Set<String> = []

    func walk(roots: [String], isCancelled: @escaping () -> Bool, progress: @escaping (Progress) -> Void = { _ in },
              onFile: @escaping (String, FileStat) -> Void) -> Outcome {
        let run = Run(walker: self, isCancelled: isCancelled, progress: progress, onFile: onFile)
        for root in roots {
            if isCancelled() { run.outcome.cancelled = true; break }
            run.start(root: root)
        }
        return run.outcome
    }

    /// Klasör adları; açılamazsa errno.
    static func listNames(_ path: String) -> (names: [String], error: Int32?) {
        guard let dir = opendir(path) else { return ([], errno) }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafeMutablePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            names.append(name)
        }
        return (names, nil)
    }

    private struct LinkKey: Hashable {
        var dev: Int32
        var ino: UInt64
    }

    private final class Run {
        let walker: FileWalker
        let isCancelled: () -> Bool
        let progress: (Progress) -> Void
        let onFile: (String, FileStat) -> Void
        var outcome = Outcome()
        var seenLinks = Set<LinkKey>()
        var seenDirs = Set<LinkKey>()
        var rootDev: Int32 = 0

        init(walker: FileWalker, isCancelled: @escaping () -> Bool, progress: @escaping (Progress) -> Void,
             onFile: @escaping (String, FileStat) -> Void) {
            self.walker = walker
            self.isCancelled = isCancelled
            self.progress = progress
            self.onFile = onFile
        }

        func start(root: String) {
            let resolved = CleanupDeleter.realPath(root) ?? root
            guard let st = walker.stat.lstat(resolved), st.isDirectory else {
                outcome.rootStates[root] = .missing
                return
            }
            let listing = FileWalker.listNames(resolved)
            if let error = listing.error {
                outcome.rootStates[root] = (error == EPERM || error == EACCES) ? .noAccess : .missing
                return
            }
            outcome.rootStates[root] = .scanned
            rootDev = st.dev
            progress(Progress(files: outcome.filesSeen, directory: resolved))
            visit(dir: resolved, stat: st, names: listing.names)
        }

        private func visit(dir: String, stat dirStat: FileStat, names: [String]) {
            guard seenDirs.insert(LinkKey(dev: dirStat.dev, ino: dirStat.ino)).inserted else { return }
            var subdirs: [String] = []
            for name in names.sorted() {
                if isCancelled() { outcome.cancelled = true; return }
                let path = dir + "/" + name
                guard let st = walker.stat.lstat(path), !st.isSymlink, !st.isDataless else { continue }
                if st.isDirectory {
                    if st.dev != rootDev || FileWalker.isPackage(name) || walker.skipPaths.contains(path) { continue }
                    subdirs.append(path)
                } else if st.isRegular {
                    outcome.filesSeen += 1
                    if outcome.filesSeen % 256 == 0 { progress(Progress(files: outcome.filesSeen, directory: dir)) }
                    if st.nlink > 1, !seenLinks.insert(LinkKey(dev: st.dev, ino: st.ino)).inserted { continue }
                    onFile(path, st)
                }
            }
            for sub in subdirs {
                if outcome.cancelled || isCancelled() { outcome.cancelled = true; return }
                guard let st = walker.stat.lstat(sub) else { continue }
                let listing = FileWalker.listNames(sub)
                if listing.error != nil { outcome.unreadableDirs += 1; continue }
                progress(Progress(files: outcome.filesSeen, directory: sub))
                visit(dir: sub, stat: st, names: listing.names)
            }
        }
    }
}
