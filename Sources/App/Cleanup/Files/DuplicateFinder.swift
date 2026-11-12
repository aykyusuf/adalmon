import CryptoKit
import Darwin
import Foundation

struct DuplicateFile: Identifiable, Sendable, Equatable {
    var id: String { path }
    let path: String
    let dev: Int32
    let ino: UInt64
    /// Mantıksal boyut (eşleme bununla yapılır).
    let size: UInt64
    let allocated: UInt64
    let modified: Date

    var name: String { (path as NSString).lastPathComponent }

    func candidate(roots: [String]) -> DeletionCandidate {
        DeletionCandidate(path: path, dev: dev, ino: ino, bytes: allocated, kind: DuplicateFinder.kind,
                          scope: .descendant(roots: roots, nameAllowlist: nil), displayName: name)
    }
}

/// Aynı içerikli dosyalar. `files` varsayılan korunacak dosya başta olacak biçimde sıralıdır.
struct DuplicateGroup: Identifiable, Sendable, Equatable {
    let id: String
    let size: UInt64
    let files: [DuplicateFile]

    var defaultKeeper: DuplicateFile { files[0] }
    /// Bir kopya kalırsa açılacak en çok yer (APFS klonlarında gerçekte ~0 olabilir).
    var reclaimableBytes: UInt64 { files.dropFirst().reduce(0) { $0 + $1.allocated } }

    /// En eski, eşitse en kısa yol, eşitse alfabetik.
    static func keeperOrder(_ a: DuplicateFile, _ b: DuplicateFile) -> Bool {
        if a.modified != b.modified { return a.modified < b.modified }
        if a.path.count != b.path.count { return a.path.count < b.path.count }
        return a.path < b.path
    }
}

struct DuplicateResult: Sendable, Equatable {
    var groups: [DuplicateGroup] = []
    var rootStates: [String: CleanupRootState] = [:]
    var unreadableDirs = 0
    var filesSeen = 0
    var cancelled = false

    var reclaimableBytes: UInt64 { groups.reduce(0) { $0 + $1.reclaimableBytes } }
}

struct DuplicateFinder: Sendable {
    static let kind: CleanupKind = "files.duplicates"
    static let defaultMinBytes: UInt64 = 1 << 20
    static let prefixBytes = 64 << 10
    static let chunkBytes = 1 << 20

    enum Phase: Sendable, Equatable { case listing, prefixHash, fullHash }

    struct Progress: Sendable, Equatable {
        var phase: Phase
        var done: Int
        var total: Int
        var detail: String
    }

    var minBytes: UInt64 = defaultMinBytes
    var stat: StatProvider = .live
    var skipPaths: Set<String> = []

    /// 1) boyuta göre grupla, 2) ilk 64 KB SHA-256, 3) yalnızca hâlâ eşleşenler için tam SHA-256 (1 MB parçalarla).
    func find(roots: [String], isCancelled: @escaping () -> Bool = { false },
              progress: @escaping (Progress) -> Void = { _ in }) -> DuplicateResult {
        var bySize: [UInt64: [DuplicateFile]] = [:]
        let threshold = minBytes
        let walker = FileWalker(stat: stat, skipPaths: skipPaths)
        let outcome = walker.walk(roots: roots, isCancelled: isCancelled, progress: { p in
            progress(Progress(phase: .listing, done: p.files, total: 0, detail: p.directory))
        }) { path, st in
            guard st.size >= threshold else { return }
            bySize[st.size, default: []].append(DuplicateFile(path: path, dev: st.dev, ino: st.ino, size: st.size, allocated: st.allocated, modified: st.mtime))
        }
        var result = DuplicateResult(rootStates: outcome.rootStates, unreadableDirs: outcome.unreadableDirs,
                                     filesSeen: outcome.filesSeen, cancelled: outcome.cancelled)
        if outcome.cancelled { return result }

        let sizeGroups = bySize.values.filter { $0.count > 1 }
        var prefixGroups: [(digest: Data, files: [DuplicateFile])] = []
        let prefixTotal = sizeGroups.reduce(0) { $0 + $1.count }
        var done = 0
        for group in sizeGroups {
            var byPrefix: [Data: [DuplicateFile]] = [:]
            for file in group {
                if isCancelled() { result.cancelled = true; return result }
                done += 1
                progress(Progress(phase: .prefixHash, done: done, total: prefixTotal, detail: file.path))
                guard case .digest(let digest) = Self.hash(path: file.path, expectedSize: file.size, limit: Self.prefixBytes, isCancelled: isCancelled) else {
                    if isCancelled() { result.cancelled = true; return result }
                    continue
                }
                byPrefix[digest, default: []].append(file)
            }
            prefixGroups += byPrefix.filter { $0.value.count > 1 }.map { (digest: $0.key, files: $0.value) }
        }

        let fullTotal = prefixGroups.reduce(0) { $0 + $1.files.count }
        done = 0
        var groups: [DuplicateGroup] = []
        for (prefixDigest, group) in prefixGroups {
            // Dosya 64 KB'a sığıyorsa ilk-64-KB özeti zaten tam özettir.
            if let size = group.first?.size, size <= UInt64(Self.prefixBytes) {
                done += group.count
                groups += Self.makeGroup(from: group, digest: prefixDigest)
                continue
            }
            var byFull: [Data: [DuplicateFile]] = [:]
            for file in group {
                if isCancelled() { result.cancelled = true; return result }
                done += 1
                progress(Progress(phase: .fullHash, done: done, total: fullTotal, detail: file.path))
                guard case .digest(let digest) = Self.hash(path: file.path, expectedSize: file.size, limit: nil, isCancelled: isCancelled) else {
                    if isCancelled() { result.cancelled = true; return result }
                    continue
                }
                byFull[digest, default: []].append(file)
            }
            for (digest, files) in byFull where files.count > 1 {
                groups += Self.makeGroup(from: files, digest: digest)
            }
        }
        result.groups = groups.sorted { $0.reclaimableBytes != $1.reclaimableBytes ? $0.reclaimableBytes > $1.reclaimableBytes : $0.id < $1.id }
        return result
    }

    private static func makeGroup(from files: [DuplicateFile], digest: Data) -> [DuplicateGroup] {
        let sorted = files.sorted(by: DuplicateGroup.keeperOrder)
        guard sorted.count > 1, let first = sorted.first else { return [] }
        let digestText = digest.map { String(format: "%02x", $0) }.joined()
        return [DuplicateGroup(id: "\(first.size)-\(digestText)", size: first.size, files: sorted)]
    }

    // MARK: Özet

    enum HashOutcome: Sendable, Equatable {
        case digest(Data)
        case failed
        case cancelled
    }

    /// `limit` nil ise tüm dosya, değilse ilk `limit` bayt. Sembolik bağ izlenmez; okurken dosya değiştiyse `.failed`.
    static func hash(path: String, expectedSize: UInt64, limit: Int?, chunk: Int = chunkBytes, isCancelled: () -> Bool) -> HashOutcome {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return .failed }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1) // tek seferlik okuma sistem önbelleğini doldurmasın
        var before = Darwin.stat()
        guard fstat(fd, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG, UInt64(max(0, before.st_size)) == expectedSize else { return .failed }

        let bufferSize = max(1, min(chunk, limit ?? chunk))
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if isCancelled() { return .cancelled }
            let n = read(fd, buffer, min(bufferSize, remaining))
            if n < 0 { return .failed }
            if n == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: n))
            remaining -= n
        }
        var after = Darwin.stat()
        guard fstat(fd, &after) == 0, after.st_size == before.st_size,
              after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec, after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec else { return .failed }
        return .digest(Data(hasher.finalize()))
    }
}

/// Hangi kopyaların silineceği. Her grupta bir "korunan" dosya vardır ve seçilemez; böylece bir grubun hepsi asla seçilmez.
struct DuplicateSelection: Equatable, Sendable {
    private(set) var keepers: [String: String] = [:]
    private(set) var selected: Set<String> = []
    private var groupOf: [String: String] = [:]

    init(groups: [DuplicateGroup]) {
        for group in groups {
            keepers[group.id] = group.defaultKeeper.path
            for file in group.files { groupOf[file.path] = group.id }
        }
    }

    func keeper(of group: DuplicateGroup) -> String { keepers[group.id] ?? group.defaultKeeper.path }

    func isSelected(_ path: String) -> Bool { selected.contains(path) }

    /// Korunan dosya seçilemez; yanlış gruptan gelen yol reddedilir.
    @discardableResult
    mutating func toggle(_ path: String, in group: DuplicateGroup) -> Bool {
        guard groupOf[path] == group.id, path != keeper(of: group) else { return false }
        if selected.contains(path) { selected.remove(path) } else { selected.insert(path) }
        return true
    }

    /// Yeni korunan dosyayı belirler; seçiliyse seçimden çıkar.
    mutating func setKeeper(_ path: String, in group: DuplicateGroup) {
        guard groupOf[path] == group.id else { return }
        keepers[group.id] = path
        selected.remove(path)
    }

    /// Her gruptaki korunan dışındaki tüm dosyaları seçer.
    mutating func selectAllButKeepers(in groups: [DuplicateGroup]) {
        for group in groups {
            let keep = keeper(of: group)
            for file in group.files where file.path != keep { selected.insert(file.path) }
        }
    }

    mutating func clear() { selected.removeAll() }

    /// Seçimi verilen yollarla sınırlar (onay penceresinde gösterilenler).
    mutating func restrict(to paths: Set<String>) { selected.formIntersection(paths) }

    /// Yeniden kurulan gruplarda önceki korunan dosya ve seçimleri (hâlâ geçerliyse) geri getirir.
    mutating func restore(from old: DuplicateSelection, in groups: [DuplicateGroup]) {
        for group in groups {
            if let kept = old.keepers[group.id], group.files.contains(where: { $0.path == kept }) { keepers[group.id] = kept }
            let keep = keeper(of: group)
            for file in group.files where file.path != keep && old.selected.contains(file.path) { selected.insert(file.path) }
        }
    }

    func selectedFiles(in groups: [DuplicateGroup]) -> [DuplicateFile] {
        groups.flatMap { group in
            let keep = keeper(of: group)
            return group.files.filter { selected.contains($0.path) && $0.path != keep }
        }
    }

    /// Silmeden hemen önce: korunan dosya yerinde ve taramadaki gibi olmalı, silinecekler de değişmemiş olmalı.
    /// Korunan dosya kaybolduysa o grubun hiçbir dosyası silinmez.
    func verifiedDeletions(in groups: [DuplicateGroup], stat: StatProvider = .live) -> (deletable: [DuplicateFile], refused: [(file: DuplicateFile, reason: String)]) {
        func unchanged(_ file: DuplicateFile) -> Bool {
            guard let st = stat.lstat(file.path), st.isRegular else { return false }
            return st.dev == file.dev && st.ino == file.ino && st.size == file.size && st.mtime == file.modified
        }
        var deletable: [DuplicateFile] = []
        var refused: [(file: DuplicateFile, reason: String)] = []
        for group in groups {
            let keep = keeper(of: group)
            let chosen = group.files.filter { selected.contains($0.path) && $0.path != keep }
            guard !chosen.isEmpty else { continue }
            guard let keptFile = group.files.first(where: { $0.path == keep }), unchanged(keptFile) else {
                refused += chosen.map { ($0, "Korunan kopya değişmiş ya da yok") }
                continue
            }
            for file in chosen {
                if unchanged(file) { deletable.append(file) } else { refused.append((file, "Taramadan sonra değişmiş")) }
            }
        }
        return (deletable, refused)
    }
}
