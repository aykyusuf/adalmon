import Darwin
import Foundation

/// Taranacak kök klasör. `maxDepth`: kökün kaç düzey altına kadar alt klasör boyutları da kaydedilir (0 = yalnız kök).
struct FolderScanRoot: Sendable, Equatable {
    var path: String
    var maxDepth: Int
    /// Kökün DOĞRUDAN çocuklarından atlananlar (TCC korumalı / sistem verisi).
    var skipChildNames: Set<String> = []
    var skipChildPrefixes: [String] = []
    /// Bu kök en çok kaç saatte bir taranır (ağır / seyrek değişen kökler 3 ya da 6 saatte bir: pil; ölçüm: tüm kökler ≈5 sn CPU). Aradaki saatlerde önceki değer taşınır.
    var everyHours = 1

    func skips(_ name: String) -> Bool {
        skipChildNames.contains(name) || skipChildPrefixes.contains { name.hasPrefix($0) }
    }
}

/// `getattrlistbulk` ile ayrılmış (allocated) boyut taraması. Sembolik bağ izlemez, aynı cihazda kalır,
/// sabit bağları (hardlink) (dev, fileid) ile bir kez sayar. İzin yoksa sessizce atlar (istem tetiklemez:
/// yalnızca kullanıcı verisi dışındaki korumasız klasörler listelenir, bkz. `FolderWatchList`).
enum FolderScanner {
    struct Result: Sendable, Equatable {
        var totalBytes: UInt64 = 0
        var files = 0
        var unreadableDirs = 0
        var entries: [FolderSnapshotEntry] = []
    }

    private struct LinkKey: Hashable {
        var dev: Int32
        var fileID: UInt64
    }

    private struct Context {
        var rootDev: Int32 = 0
        var seen = Set<LinkKey>()
        var files = 0
        var unreadable = 0
        var entries: [FolderSnapshotEntry] = []
        let root: FolderScanRoot
        let minRecorded: UInt64
        let isCancelled: () -> Bool
    }

    /// Bundan küçük alt klasörler kaydedilmez. Önceki taramada kayıt yoksa "<10 MB" demektir: büyüme hesabı bu tabandan başlar.
    static let defaultMinRecordedBytes: UInt64 = 10 << 20

    /// - Parameter minRecordedBytes: bundan küçük alt klasörler kaydedilmez (kökün toplamı her zaman kaydedilir).
    static func scan(root: FolderScanRoot, minRecordedBytes: UInt64 = defaultMinRecordedBytes, isCancelled: @escaping () -> Bool = { false }) -> Result? {
        var st = stat()
        guard lstat(root.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return nil }
        var ctx = Context(rootDev: st.st_dev, root: root, minRecorded: minRecordedBytes, isCancelled: isCancelled)
        // Kökün cihaz numarası stat'taki değil getattrlist'tekidir; ilk girişte aynı alan okunur.
        ctx.rootDev = deviceID(of: root.path) ?? st.st_dev
        let total = size(of: root.path, depth: 0, ctx: &ctx)
        ctx.entries.append(FolderSnapshotEntry(path: root.path, depth: 0, bytes: total))
        return Result(totalBytes: total, files: ctx.files, unreadableDirs: ctx.unreadable, entries: ctx.entries)
    }

    private static func deviceID(of path: String) -> Int32? {
        var al = attrlist()
        al.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        al.commonattr = attrgroup_t(ATTR_CMN_DEVID)
        var buf = [UInt8](repeating: 0, count: 16)
        guard getattrlist(path, &al, &buf, buf.count, 0) == 0 else { return nil }
        return buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int32.self) }
    }

    private static func size(of path: String, depth: Int, ctx: inout Context) -> UInt64 {
        if ctx.isCancelled() { return 0 }
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            ctx.unreadable += 1
            return 0
        }

        var al = attrlist()
        al.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        al.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FILEID)
        al.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

        let bufSize = 128 * 1024
        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { buf.deallocate() }

        var total: UInt64 = 0
        var subdirs: [String] = []
        while true {
            let n = getattrlistbulk(fd, &al, buf, bufSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
            if n <= 0 {
                if n < 0 { ctx.unreadable += 1 }
                break
            }
            var p = UnsafeRawPointer(buf)
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
                    ctx.files += 1
                    // Sabit bağ: aynı (dev, fileid) bir kez sayılır.
                    if linkCount > 1, !ctx.seen.insert(LinkKey(dev: dev, fileID: fileID)).inserted { /* zaten sayıldı */ } else {
                        total &+= alloc
                    }
                } else if objType == UInt32(VDIR.rawValue) {
                    // Ad yalnızca klasörler için String'e çevrilir (dosya başına ayırma yapılmaz: CPU).
                    if dev != 0, dev != ctx.rootDev { /* başka birim (bağlama noktası) */ }
                    else if let namePointer {
                        let name = String(cString: namePointer)
                        if depth == 0, ctx.root.skips(name) { /* korumalı / atlanan */ } else { subdirs.append(name) }
                    }
                }
                p = entryStart + length
            }
        }
        close(fd)

        for name in subdirs {
            let child = path + "/" + name
            let s = size(of: child, depth: depth + 1, ctx: &ctx)
            total &+= s
            if depth + 1 <= ctx.root.maxDepth, s >= ctx.minRecorded {
                ctx.entries.append(FolderSnapshotEntry(path: child, depth: depth + 1, bytes: s))
            }
        }
        return total
    }
}

/// Saatlik taranacak anahtar klasörler. Korumalı yerlere (Containers, Group Containers, Mail, Safari, Messages, Photos,
/// Desktop/Documents/Downloads, ~/.Trash) ASLA girilmez: arka planda izin istemi çıkmasın.
enum FolderWatchList {
    /// `~/Library/Application Support` altında atlananlar: izin istemi / FDA gerektirenler (sessiz EPERM) ve Apple sistem verisi.
    static let appSupportSkipNames: Set<String> = [
        "MobileSync", "AddressBook", "CallHistoryDB", "CallHistoryTransactions", "Knowledge", "CloudDocs", "FileProvider",
        "DifferentialPrivacy", "SyncServices", "iCloud", "Mail", "Messages", "Safari", "Photos", "Containers", "Group Containers",
        "com.apple.TCC", "com.apple.sharedfilelist", "CrashReporter", "Animoji",
    ]
    static let cachesSkipNames: Set<String> = [
        "com.apple.Safari", "com.apple.mail", "com.apple.Maps", "com.apple.homed", "com.apple.photolibraryd", "com.apple.Photos",
        "com.apple.Messages", "com.apple.AddressBook", "FamilyCircle", "CloudKit",
    ]

    static func roots(home: String = NSHomeDirectory()) -> [FolderScanRoot] {
        let lib = home + "/Library"
        var roots: [FolderScanRoot] = [
            FolderScanRoot(path: lib + "/Caches", maxDepth: 1, skipChildNames: cachesSkipNames),
            FolderScanRoot(path: lib + "/Developer", maxDepth: 2),
            FolderScanRoot(path: lib + "/Application Support", maxDepth: 1, skipChildNames: appSupportSkipNames,
                           skipChildPrefixes: ["com.apple."], everyHours: 3),
            FolderScanRoot(path: lib + "/Logs", maxDepth: 1, skipChildNames: ["DiagnosticReports"]),
            FolderScanRoot(path: home + "/.cache", maxDepth: 1, everyHours: 3),
            FolderScanRoot(path: home + "/.npm", maxDepth: 1, everyHours: 3),
            FolderScanRoot(path: home + "/.gradle", maxDepth: 1, everyHours: 6),
            FolderScanRoot(path: home + "/.pub-cache", maxDepth: 1, everyHours: 3),
            // Docker Desktop verisi ~/Library/Containers altında (izin istemi riski); yalnız Containers dışı motorlar.
            FolderScanRoot(path: home + "/.docker", maxDepth: 1, everyHours: 6),
            FolderScanRoot(path: home + "/.colima", maxDepth: 2, everyHours: 6),
            FolderScanRoot(path: home + "/.lima", maxDepth: 2, everyHours: 6),
            FolderScanRoot(path: home + "/.orbstack", maxDepth: 2, everyHours: 6),
        ]
        for dir in darwinUserDirs() { roots.append(FolderScanRoot(path: dir, maxDepth: 1)) }
        return roots
    }

    /// `/private/var/folders/xx/yyyy/T` ve `/C` (kullanıcıya özel geçici ve önbellek).
    static func darwinUserDirs() -> [String] {
        var out: [String] = []
        for name in [Int32(_CS_DARWIN_USER_TEMP_DIR), Int32(_CS_DARWIN_USER_CACHE_DIR)] {
            var buf = [CChar](repeating: 0, count: 1_024)
            guard confstr(name, &buf, buf.count) > 0 else { continue }
            var path = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }
            if let real = realpath(path, nil) {
                path = String(cString: real)
                free(real)
            }
            if !out.contains(path) { out.append(path) }
        }
        return out
    }

    /// Gösterim: ana dizin `~` olur.
    static func displayPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
