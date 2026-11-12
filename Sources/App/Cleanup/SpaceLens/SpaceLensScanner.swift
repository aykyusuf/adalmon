import Darwin
import Foundation

/// Treemap'teki bir kutu: bir klasör, bir dosya ya da taranmayan korumalı bir klasör.
struct SpaceNode: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case folder
        case file
        /// Erişim reddedildi (TCC); boyut bilinmez. Erişim akışı gösterilir.
        case locked(AccessReason)
        /// Bilerek taranmadı (başka uygulamaların verisi, iCloud/dosya sağlayıcıları).
        case skipped(AccessReason?)
    }

    var id: String { path }
    let path: String
    let kind: Kind
    let bytes: UInt64

    var name: String { (path as NSString).lastPathComponent }
    var isFolder: Bool { kind == .folder }
    /// Yerleşimde yer kaplar (boyutu bilinen).
    var isMeasured: Bool {
        switch kind {
        case .folder, .file: true
        case .locked, .skipped: false
        }
    }
}

/// Bir klasörün doğrudan alt öğeleri. Küçük (ya da sınırı aşan) öğeler tek tek tutulmaz: `otherBytes` içinde toplanır.
struct SpaceDir: Sendable, Equatable {
    /// Büyükten küçüğe; ölçülemeyen (kilitli/atlanan) öğeler sonda.
    var nodes: [SpaceNode]
    var otherBytes: UInt64
    var otherCount: Int
    var totalBytes: UInt64

    init(nodes: [SpaceNode], otherBytes: UInt64 = 0, otherCount: Int = 0) {
        self.nodes = nodes
        self.otherBytes = otherBytes
        self.otherCount = otherCount
        totalBytes = nodes.reduce(otherBytes) { $0 + $1.bytes }
    }

    /// Alt klasörün boyutu değişti (yeniden tarama): düğümü günceller, sırayı ve toplamı yeniler.
    func replacingFolder(_ path: String, bytes newBytes: UInt64) -> SpaceDir? {
        guard let index = nodes.firstIndex(where: { $0.path == path && $0.isFolder }) else { return nil }
        var copy = nodes
        copy[index] = SpaceNode(path: path, kind: .folder, bytes: newBytes)
        copy.sort(by: SpaceLensScanner.order)
        return SpaceDir(nodes: copy, otherBytes: otherBytes, otherCount: otherCount)
    }
}

/// Bir taramanın sonucu: kökten başlayan alt ağacın tamamı (klasör yolu → doğrudan öğeleri).
/// `dirs`te olmayan bir klasör düğümü "tembel"dir: boyutu bilinir ama içi henüz taranmamıştır.
struct SpaceLensScan: Sendable, Equatable {
    var root = ""
    var dirs: [String: SpaceDir] = [:]
    var state: CleanupRootState = .scanned
    var cancelled = false

    var nodes: [SpaceNode] { dirs[root]?.nodes ?? [] }
}

/// Önbellek tarayıcısı için sözleşme (testlerde sayaçlı sarmalayıcı enjekte edilir).
protocol SpaceTreeScanning: Sendable {
    func scan(path: String, isCancelled: @escaping () -> Bool,
              progress: @escaping (_ done: Int, _ total: Int, _ name: String) -> Void) -> SpaceLensScan
}

/// Bir klasörün alt ağacını TEK geçişte ölçer (`getattrlistbulk`): her klasörün boyutu ve büyük öğeleri bellekte bir ağaç olarak
/// döner; böylece içine girmek yeniden tarama gerektirmez. Küçük öğeler "diğer"de birleşir, düğüm sayısı tavanı aşılırsa en derin
/// seviyeler tembel bırakılır (sonradan istek üzerine taranır). Salt okunurdur.
struct SpaceLensScanner: SpaceTreeScanning {
    /// `~/Library` altında başka uygulamaların verisi / dosya sağlayıcıları: açılmaz (izin penceresi çıkarmasın, iCloud inmesin).
    static let librarySkipNames: Set<String> = ["Containers", "Group Containers", "Mail", "Messages", "Safari", "Mobile Documents", "CloudStorage"]
    /// Bundan küçük öğeler tek tek tutulmaz.
    static let defaultMinKeepBytes: UInt64 = 1 << 20
    static let defaultMaxChildren = 200
    /// Bir taramanın bellekte tutacağı en çok düğüm (yaklaşık 15 MB).
    static let defaultMaxStoredNodes = 100_000

    var home: String = NSHomeDirectory()
    var probe: PathProbe = .live
    var minKeepBytes = SpaceLensScanner.defaultMinKeepBytes
    var maxChildren = SpaceLensScanner.defaultMaxChildren
    var maxStoredNodes = SpaceLensScanner.defaultMaxStoredNodes

    /// Atlanan `~/Library` klasörü için erişim nedeni (iCloud/dosya sağlayıcıları için yok).
    static func skipReason(forName name: String) -> AccessReason? {
        switch name {
        case "Containers", "Group Containers": .appData
        case "Mail", "Messages", "Safari": .fullDiskAccess
        default: nil
        }
    }

    func isSkipped(_ path: String) -> Bool {
        let library = home + "/Library"
        return (path as NSString).deletingLastPathComponent == library && Self.librarySkipNames.contains((path as NSString).lastPathComponent)
    }

    /// Büyükten küçüğe; eşitlikte yola göre.
    static func order(_ a: SpaceNode, _ b: SpaceNode) -> Bool {
        a.bytes != b.bytes ? a.bytes > b.bytes : a.path < b.path
    }

    func scan(path: String, isCancelled: @escaping () -> Bool = { false },
              progress: @escaping (_ done: Int, _ total: Int, _ name: String) -> Void = { _, _, _ in }) -> SpaceLensScan {
        switch probe.check(path) {
        case .missing: return SpaceLensScan(root: path, state: .missing)
        case .denied: return SpaceLensScan(root: path, state: .noAccess)
        case .ok: break
        }
        let walk = Walk(scanner: self, rootDev: Self.deviceID(of: path), isCancelled: isCancelled, progress: progress)
        defer { walk.buffer.deallocate() }
        switch walk.visit(path, depth: 0) {
        case .missing: return SpaceLensScan(root: path, state: .missing)
        case .denied: return SpaceLensScan(root: path, state: .noAccess)
        case .size: break
        }
        if walk.cancelled { return SpaceLensScan(root: path, cancelled: true) }
        return SpaceLensScan(root: path, dirs: Self.prune(walk.dirs, root: path, maxNodes: maxStoredNodes))
    }

    /// Kökten seviye seviye ilerler: ulaşılamayan (üst sınırı aşıp düşen) kayıtları atar ve düğüm tavanını aşan ilk seviyeden
    /// itibaren klasörleri tembel bırakır. Kök ve ilk seviye her zaman kalır.
    static func prune(_ dirs: [String: SpaceDir], root: String, maxNodes: Int) -> [String: SpaceDir] {
        var out: [String: SpaceDir] = [:]
        var level = [root]
        var count = 0
        var depth = 0
        while !level.isEmpty {
            var next: [String] = []
            var levelNodes = 0
            for path in level {
                guard let dir = dirs[path] else { continue }
                levelNodes += dir.nodes.count
                next.append(contentsOf: dir.nodes.lazy.filter(\.isFolder).map(\.path))
            }
            if depth >= 2, count + levelNodes > maxNodes { break }
            for path in level { out[path] = dirs[path] }
            count += levelNodes
            level = next
            depth += 1
        }
        return out
    }

    private static func deviceID(of path: String) -> Int32 {
        var al = attrlist()
        al.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        al.commonattr = attrgroup_t(ATTR_CMN_DEVID)
        var buf = [UInt8](repeating: 0, count: 16)
        if getattrlist(path, &al, &buf, buf.count, 0) == 0 {
            return buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int32.self) }
        }
        var st = stat()
        return lstat(path, &st) == 0 ? st.st_dev : 0
    }

    private struct LinkKey: Hashable {
        var dev: Int32
        var fileID: UInt64
    }

    private enum Visit {
        case size(UInt64)
        case denied
        case missing
    }

    private final class Walk {
        let scanner: SpaceLensScanner
        let rootDev: Int32
        let isCancelled: () -> Bool
        let progress: (Int, Int, String) -> Void
        let bufSize = 128 * 1024
        let buffer: UnsafeMutableRawPointer
        var seen = Set<LinkKey>()
        var dirs: [String: SpaceDir] = [:]
        var cancelled = false
        var topDone = 0
        var topTotal = 0
        var attrs: attrlist

        init(scanner: SpaceLensScanner, rootDev: Int32, isCancelled: @escaping () -> Bool, progress: @escaping (Int, Int, String) -> Void) {
            self.scanner = scanner
            self.rootDev = rootDev
            self.isCancelled = isCancelled
            self.progress = progress
            buffer = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
            var al = attrlist()
            al.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
            al.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID)
                | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FILEID)
            al.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
            attrs = al
        }

        func visit(_ path: String, depth: Int) -> Visit {
            if cancelled || isCancelled() { cancelled = true; return .size(0) }
            let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if fd < 0 { return (errno == EPERM || errno == EACCES) ? .denied : .missing }
            if depth <= 2 { progress(topDone, topTotal, (path as NSString).lastPathComponent) }

            var total: UInt64 = 0
            var measured: [SpaceNode] = []
            var small: UInt64 = 0
            var smallCount = 0
            var subdirs: [String] = []
            let minKeep = scanner.minKeepBytes
            while true {
                if isCancelled() { cancelled = true; break }
                let n = getattrlistbulk(fd, &attrs, buffer, bufSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
                if n <= 0 { break }
                var p = UnsafeRawPointer(buffer)
                for _ in 0..<Int(n) {
                    let entryStart = p
                    let length = Int(p.loadUnaligned(as: UInt32.self))
                    p += 4
                    let returned = p.loadUnaligned(as: attribute_set_t.self)
                    p += MemoryLayout<attribute_set_t>.size
                    var namePointer: UnsafePointer<CChar>?
                    if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                        let ref = p.loadUnaligned(as: attrreference_t.self)
                        namePointer = (p + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                        p += MemoryLayout<attrreference_t>.size
                    }
                    var dev: Int32 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_DEVID) != 0 { dev = p.loadUnaligned(as: Int32.self); p += 4 }
                    var objType: UInt32 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 { objType = p.loadUnaligned(as: UInt32.self); p += 4 }
                    var fileID: UInt64 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 { fileID = p.loadUnaligned(as: UInt64.self); p += 8 }
                    var linkCount: UInt32 = 1
                    if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 { linkCount = p.loadUnaligned(as: UInt32.self); p += 4 }
                    var alloc: UInt64 = 0
                    if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 { alloc = UInt64(bitPattern: p.loadUnaligned(as: Int64.self)); p += 8 }

                    if objType == UInt32(VREG.rawValue) {
                        // Sabit bağ: aynı (dev, fileid) bir kez sayılır.
                        if linkCount > 1, !seen.insert(LinkKey(dev: dev, fileID: fileID)).inserted {
                            // zaten sayıldı
                        } else if alloc > 0 {
                            total &+= alloc
                            if alloc >= minKeep, let namePointer {
                                measured.append(SpaceNode(path: path + "/" + String(cString: namePointer), kind: .file, bytes: alloc))
                            } else {
                                small &+= alloc
                                smallCount += 1
                            }
                        }
                    } else if objType == UInt32(VDIR.rawValue) {
                        // Başka birim (bağlama noktası) gezilmez.
                        if dev != 0, dev != rootDev {
                            // atla
                        } else if let namePointer {
                            subdirs.append(String(cString: namePointer))
                        }
                    }
                    p = entryStart + length
                }
            }
            close(fd)
            if cancelled { return .size(0) }

            subdirs.sort()
            if depth == 0 { topTotal = subdirs.count }
            var others: [SpaceNode] = []
            for (index, name) in subdirs.enumerated() {
                if depth == 0 { topDone = index }
                let child = path + "/" + name
                if scanner.isSkipped(child) {
                    others.append(SpaceNode(path: child, kind: .skipped(SpaceLensScanner.skipReason(forName: name)), bytes: 0))
                    continue
                }
                // İlk seviyelerde izin penceresi/erişim sınıflaması için açma denemesi (TCC); derinde `open` hatası yeter.
                if depth <= 1 {
                    switch scanner.probe.check(child) {
                    case .missing: continue
                    case .denied:
                        others.append(SpaceNode(path: child, kind: .locked(CleanupAccess.reason(for: child, home: scanner.home)), bytes: 0))
                        continue
                    case .ok: break
                    }
                }
                switch visit(child, depth: depth + 1) {
                case .missing: continue
                case .denied:
                    others.append(SpaceNode(path: child, kind: .locked(CleanupAccess.reason(for: child, home: scanner.home)), bytes: 0))
                case .size(let size):
                    if cancelled { return .size(0) }
                    total &+= size
                    if size >= minKeep {
                        measured.append(SpaceNode(path: child, kind: .folder, bytes: size))
                    } else {
                        small &+= size
                        smallCount += 1
                    }
                }
            }

            measured.sort(by: SpaceLensScanner.order)
            if measured.count > scanner.maxChildren {
                let tail = measured[scanner.maxChildren...]
                small &+= tail.reduce(0) { $0 + $1.bytes }
                smallCount += tail.count
                for node in tail { dirs[node.path] = nil }
                measured.removeSubrange(scanner.maxChildren...)
            }
            others.sort { $0.path < $1.path }
            // Küçük klasörün kaydı tutulmaz (üstünde "diğer"e katılır); bellek yalnızca anlamlı klasörler için harcanır.
            if depth == 0 || total >= minKeep {
                dirs[path] = SpaceDir(nodes: measured + others, otherBytes: small, otherCount: smallCount)
            }
            return .size(total)
        }
    }
}
