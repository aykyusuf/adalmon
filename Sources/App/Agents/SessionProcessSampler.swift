import Darwin
import Foundation

/// Süreç tablosundaki bir satır (komut satırı YOK; yalnızca kimlik, ad, durum ve başlangıç).
struct ProcessTableEntry: Equatable, Sendable {
    var pid: Int32
    var ppid: Int32
    /// Çekirdeğin kısa süreç adı (`pbi_name`/`p_comm`).
    var name: String
    var isZombie: Bool
    var startedAt: Date?
}

/// Bir sürecin kaynak kullanımı: toplam CPU süresi (ns) ve fiziksel bellek.
struct ProcessUsageSample: Equatable, Sendable {
    var cpuNanoseconds: UInt64
    var rssBytes: UInt64
}

/// Süreç tablosu kaynağı; testlerde sahte tablo enjekte edilir. `argv` YALNIZCA sarmalayıcı sınıflandırması için okunur
/// (sampler onu sınıflandırıp atar; saklamaz, göstermez, loglamaz).
protocol ProcessTableProviding: Sendable {
    func listProcesses() -> [ProcessTableEntry]
    func usage(pid: Int32) -> ProcessUsageSample?
    /// Çalıştırılabilir dosyanın tam adı (basename); okunamazsa nil.
    func executableName(pid: Int32) -> String?
    /// İlk `argc` argüman; ortam değişkenleri okunmaz. Yalnızca Claude'un doğrudan çocuğu olan kabuklar için çağrılır.
    func argv(pid: Int32) -> [String]?
}

/// Bir oturumun arka plan işlemi. Komut satırı/argüman alanı yoktur (bilerek).
struct SessionShell: Equatable, Sendable, Identifiable {
    var pid: Int32
    var name: String
    var ageSeconds: Int
    var cpuPercent: Double
    var rssBytes: UInt64
    var hasChildren: Bool
    var id: Int32 { pid }
}

/// Bir oturumun arka plan işlemleri: en çok 12 öğe (CPU/yaşa göre sıralı), `total` ayrıca.
struct SessionShells: Equatable, Sendable {
    static let maxItems = 12
    static let empty = SessionShells(items: [], total: 0)
    var items: [SessionShell]
    var total: Int
    /// Listede gösterilmeyen işlem sayısı ("+K daha").
    var hidden: Int { max(0, total - items.count) }
}

/// Oturumun (Claude süreci) süreç ağacından Bash aracının başlattığı komut ağaçlarını bulur. Tek örnek tüm oturumlara hizmet eder;
/// CPU yüzdesi için önceki örneklemeyi (pid → CPU süresi) tutar. Komut satırı hiçbir yerde saklanmaz.
///
/// Sınıflandırma: Claude'un doğrudan çocukları arasında MCP sunucuları / hook betikleri / eklenti süreçleri vardır; yalnızca
/// "komut kökü" olan kabuk sarmalayıcıları (`zsh -c … shell-snapshots … eval …`) gösterilir. Sarmalayıcının kendisi gizlenir,
/// altındaki ilk gerçek işlem katmanı (alt kabuklar atlanır) listelenir. Sarmalayıcı sonradan `exec` ile komuta dönüşürse (aynı
/// pid + başlangıç, artık kabuk değil) süreç kendisi görünür. 2 sn'den genç süreçler ve zombiler sayılmaz.
final class SessionProcessSampler: @unchecked Sendable {
    static let minAge: TimeInterval = 2
    static let nameLimit = 24
    static let shellNames: Set<String> = ["zsh", "bash", "sh", "dash"]

    private struct Stamp { var cpuNs: UInt64; var at: Date }
    private let provider: ProcessTableProviding
    private let lock = NSLock()
    private var stamps: [Int32: Stamp] = [:]
    /// Daha önce sarmalayıcı olarak görülen süreçler (pid → başlangıç); exec devrini yakalamak için.
    private var wrappers: [Int32: Date] = [:]

    init(provider: ProcessTableProviding = LibprocProcessTable()) { self.provider = provider }

    static func isShellName(_ name: String) -> Bool { shellNames.contains(name) }

    /// Bash aracının sarmalayıcısı mı: `-c` bayrağı ve `shell-snapshots` ya da `claude` işareti (yalnızca bu karar çıkar, argv atılır).
    static func looksLikeWrapper(argv: [String]) -> Bool {
        let hasC = argv.dropFirst().contains { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("c") }
        guard hasC else { return false }
        return argv.contains { $0.contains("shell-snapshots") || $0.lowercased().contains("claude") }
    }

    /// Görünen ad: yalnızca basename, kontrol karakteri yok, 24 karakter sınırı.
    static func sanitizedName(_ raw: String) -> String {
        let base = raw.split(separator: "/").last.map(String.init) ?? raw
        let cleaned = String(String.UnicodeScalarView(base.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != "\u{7F}" }))
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "?" : String(cleaned.prefix(nameLimit))
    }

    /// Her kök (Claude pid'i) için işlemleri döndürür. Tek süreç tablosu okuması tüm kökleri karşılar.
    func sample(roots: [Int32], now: Date = .now) -> [Int32: SessionShells] {
        lock.lock(); defer { lock.unlock() }
        let table = provider.listProcesses()
        var byPid: [Int32: ProcessTableEntry] = [:]
        var children: [Int32: [ProcessTableEntry]] = [:]
        for e in table where e.pid > 0 {
            byPid[e.pid] = e
            children[e.ppid, default: []].append(e)
        }
        func liveChildren(_ pid: Int32) -> [ProcessTableEntry] { (children[pid] ?? []).filter { !$0.isZombie }.sorted { $0.pid < $1.pid } }

        var result: [Int32: SessionShells] = [:]
        var visibleAll: [Int32: [ProcessTableEntry]] = [:]
        var seenWrappers: [Int32: Date] = [:]
        for root in Set(roots) {
            guard byPid[root] != nil else { result[root] = .empty; continue }
            var visible: [ProcessTableEntry] = []
            var visited: Set<Int32> = [root]
            /// Komut kökünün altındaki ilk gerçek işlem katmanı: çocuklu alt kabuklar atlanır, diğerleri listelenir.
            func collect(_ parent: Int32) {
                for child in liveChildren(parent) where visited.insert(child.pid).inserted {
                    if Self.isShellName(child.name), !liveChildren(child.pid).isEmpty { collect(child.pid) } else { visible.append(child) }
                }
            }
            for c in liveChildren(root) where visited.insert(c.pid).inserted {
                let remembered = c.startedAt.map { wrappers[c.pid] == $0 } ?? false
                if Self.isShellName(c.name) {
                    let isWrapper = remembered || (provider.argv(pid: c.pid).map(Self.looksLikeWrapper(argv:)) ?? false)
                    guard isWrapper else { continue } // hook betiği / başka kabuk: gösterilmez
                    if let s = c.startedAt { seenWrappers[c.pid] = s }
                    collect(c.pid)
                } else if remembered {
                    if let s = c.startedAt { seenWrappers[c.pid] = s } // sonraki örneklemelerde de hatırlanır
                    visible.append(c) // sarmalayıcı exec ile komuta dönüştü
                }
            }
            visible = visible.filter { e in e.startedAt.map { now.timeIntervalSince($0) >= Self.minAge } ?? false }
            visibleAll[root] = visible
        }

        var newStamps: [Int32: Stamp] = [:]
        for (root, visible) in visibleAll {
            var shells: [SessionShell] = []
            for e in visible {
                let u = provider.usage(pid: e.pid)
                var cpu = 0.0
                if let u {
                    if let prev = stamps[e.pid], u.cpuNanoseconds >= prev.cpuNs {
                        let wall = now.timeIntervalSince(prev.at)
                        if wall > 0.05 { cpu = Double(u.cpuNanoseconds - prev.cpuNs) / (wall * 1e9) * 100 }
                    }
                    newStamps[e.pid] = Stamp(cpuNs: u.cpuNanoseconds, at: now)
                }
                let name = Self.sanitizedName(provider.executableName(pid: e.pid) ?? e.name)
                shells.append(SessionShell(pid: e.pid, name: name, ageSeconds: Self.quantizedAge(now.timeIntervalSince(e.startedAt ?? now)),
                                           cpuPercent: Self.roundedCPU(cpu), rssBytes: Self.roundedRSS(u?.rssBytes ?? 0),
                                           hasChildren: !liveChildren(e.pid).isEmpty))
            }
            shells.sort { a, b in
                if a.cpuPercent != b.cpuPercent { return a.cpuPercent > b.cpuPercent }
                if a.ageSeconds != b.ageSeconds { return a.ageSeconds > b.ageSeconds }
                return a.pid < b.pid
            }
            result[root] = SessionShells(items: Array(shells.prefix(SessionShells.maxItems)), total: shells.count)
        }
        stamps = newStamps
        wrappers = seenWrappers
        return result
    }

    // Değerler görünür duyarlığa yuvarlanır: değişmeyen durum eşit çıkar, görünüm gereksiz yenilenmez.
    static func quantizedAge(_ s: TimeInterval) -> Int { s < 60 ? Int(max(0, s) / 5) * 5 : Int(s / 60) * 60 }
    static func roundedCPU(_ v: Double) -> Double { v < 10 ? (v * 10).rounded() / 10 : v.rounded() }
    static func roundedRSS(_ b: UInt64) -> UInt64 { b / 1_048_576 * 1_048_576 }
}

/// Gerçek libproc tablosu. Yalnızca okur; sinyal göndermez, alt süreç başlatmaz.
struct LibprocProcessTable: ProcessTableProviding {
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (UInt64(max(tb.numer, 1)), UInt64(max(tb.denom, 1)))
    }()

    func listProcesses() -> [ProcessTableEntry] {
        let hint = proc_listallpids(nil, 0)
        guard hint > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(hint) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard got > 0 else { return [] }
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        var out: [ProcessTableEntry] = []
        out.reserveCapacity(Int(got))
        for pid in pids.prefix(Int(got)) where pid > 0 {
            var bsd = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { continue }
            var nameBuf = bsd.pbi_name
            var name = Self.string(from: &nameBuf)
            if name.isEmpty { var comm = bsd.pbi_comm; name = Self.string(from: &comm) }
            let start = bsd.pbi_start_tvsec > 0 ? Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000) : nil
            out.append(ProcessTableEntry(pid: pid, ppid: Int32(bitPattern: bsd.pbi_ppid), name: name, isZombie: bsd.pbi_status == UInt32(SZOMB), startedAt: start))
        }
        return out
    }

    func usage(pid: Int32) -> ProcessUsageSample? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        let ticks = info.pti_total_user &+ info.pti_total_system
        let ns = ticks / Self.timebase.denom * Self.timebase.numer + ticks % Self.timebase.denom * Self.timebase.numer / Self.timebase.denom
        return ProcessUsageSample(cpuNanoseconds: ns, rssBytes: info.pti_resident_size)
    }

    func executableName(pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        if n > 0 { return String(cString: buf).split(separator: "/").last.map(String.init) }
        var nameBuf = [CChar](repeating: 0, count: 64)
        return proc_name(pid, &nameBuf, UInt32(nameBuf.count)) > 0 ? String(cString: nameBuf) : nil
    }

    /// `KERN_PROCARGS2`: [int32 argc][çalıştırılabilir yol\0][dolgu \0…][argv0\0 … argv(argc-1)\0][ortam…]. Ortam hiç ayrıştırılmaz.
    func argv(pid: Int32) -> [String]? {
        var argMax: Int32 = 0
        var amSize = MemoryLayout<Int32>.size
        var amMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&amMib, 2, &argMax, &amSize, nil, 0) == 0, argMax > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: Int(min(argMax, 1 << 20)))
        var size = buf.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = Int(buf.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        guard argc > 0, argc < 4096 else { return nil }
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 } // çalıştırılabilir yol
        while i < size, buf[i] == 0 { i += 1 } // dolgu
        var args: [String] = []
        while args.count < argc, i < size {
            var j = i
            while j < size, buf[j] != 0 { j += 1 }
            args.append(String(decoding: buf[i..<j], as: UTF8.self))
            i = j + 1
        }
        return args
    }

    private static func string<T>(from tuple: inout T) -> String {
        withUnsafePointer(to: &tuple) { $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) } }
    }
}
