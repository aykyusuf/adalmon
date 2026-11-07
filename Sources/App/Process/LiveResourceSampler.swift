import Darwin
import Foundation

struct LiveMember: Sendable, Equatable, Identifiable {
    /// Temsilci süreç (gruplanmış üyede en küçük pid); kalan (kısa ömürlü) satırında 0.
    var pid: Int32
    var name: String
    var usage: ResourceUsage
    /// Üyenin tüm süreçleri (tek süreçte `[pid]`; çalıştırılabilire göre gruplanmış terminal üyesinde hepsi; kalanda boş).
    var pids: [pid_t]
    /// Terminal alt anahtarı (`"<terminal>|<yol>"`); tek süreç üyelerinde nil.
    var childKey: String?
    /// Çalıştırılabilir yol (Finder'da göster); yoksa nil.
    var path: String?
    var id: String { childKey ?? "pid-\(pid)" }

    init(pid: Int32, name: String, usage: ResourceUsage, pids: [pid_t]? = nil, childKey: String? = nil, path: String? = nil) {
        self.pid = pid
        self.name = name
        self.usage = usage
        self.pids = pids ?? [pid]
        self.childKey = childKey
        self.path = path
    }
}

struct LiveGroup: Sendable, Equatable, Identifiable {
    var key: String
    /// Son aralıktaki fark + güncel footprint (coalition: ölü süreçler dahil).
    var usage: ResourceUsage
    var processCount: Int
    /// Gruptaki canlı süreç kimlikleri (sonlandırma ve bilgi için).
    var pids: [pid_t] = []
    var members: [LiveMember]
    var id: String { key }
}

struct LiveSnapshot: Sendable, Equatable {
    var groups: [LiveGroup] = []
    /// Önceki örnekten beri geçen süre (sn); ilk örnekte 0 (taban çizgisi, oranlar anlamsız).
    var elapsed: Double = 0
    /// Süpürmede görülen toplam canlı süreç sayısı (Performans sekmesi).
    var totalProcessCount = 0
}

/// "Süreçler > Şu an" sayfası için canlı örnekleyici: yalnızca sayfa görünürken çağrılır. Arka plan örnekleyicisinden bağımsız
/// durum tutar (kendi önceki sayaçları). Coalition bazlı grup değerleri + üye süreç kırılımı (rusage + AppUsage GPU).
actor LiveResourceSampler {
    private let sweeper = ResourceSweeper()
    private var memberTracker = ProcessDeltaTracker()
    private var gpuTracker = GPUDeltaTracker()
    private var lastNs: UInt64 = 0
    private var names: [ProcessKey: String] = [:]
    private let timebase = MachTimebase.current
    static let maxMembersPerGroup = 25

    /// Sayfa yeniden göründüğünde eski taban çizgisi atılır (uzun boşluk).
    func reset() {
        lastNs = 0
        gpuTracker = GPUDeltaTracker()
        memberTracker = ProcessDeltaTracker()
        names = [:]
    }

    /// - Parameter expanded: üye süreç kırılımı istenen uygulama anahtarları. Yalnızca bunlar için süreç başına rusage /
    ///   ve yol okunur. GPU istemci listesi (~1,6 ms) her örnekte bir kez alınır: tüm satırların GPU yüzdesi bundan gelir.
    func sample(expanded: Set<String> = []) -> LiveSnapshot {
        let sweep = sweeper.sweep()
        let elapsed = lastNs == 0 ? 0 : Double(sweep.uptimeNs &- lastNs) / 1e9
        lastNs = sweep.uptimeNs
        let gpu = GPUClientUsage.snapshot()
        let gpuDelta = gpuTracker.update(gpu)

        var members: [String: [LiveMember]] = [:]
        if expanded.isEmpty {
            memberTracker = ProcessDeltaTracker()
            names = [:]
        } else {
            var current: [ProcessKey: ProcessCounters] = [:]
            var pidOf: [ProcessKey: pid_t] = [:]
            var owner: [ProcessKey: String] = [:]
            for key in expanded {
                // Terminal grupları süpürmeden hazır gelen çalıştırılabilir kırılımını kullanır.
                guard let group = sweep.groups[key], sweep.terminalChildren[key] == nil else { continue }
                for pid in group.pids {
                    guard let found = CoalitionAPI.processCounters(of: pid) else { continue }
                    var c = found.counters
                    c.gpuNs = gpu[pid] ?? 0
                    current[found.key] = c
                    pidOf[found.key] = pid
                    owner[found.key] = key
                }
            }
            let deltas = memberTracker.update(current, timebase: timebase)
            names = names.filter { current[$0.key] != nil }
            for (k, u) in deltas {
                guard let group = owner[k], let pid = pidOf[k] else { continue }
                if names[k] == nil {
                    let path = CoalitionAPI.path(of: pid) ?? ""
                    names[k] = path.isEmpty ? "pid \(pid)" : (path as NSString).lastPathComponent
                }
                members[group, default: []].append(LiveMember(pid: pid, name: names[k] ?? "pid \(pid)", usage: u))
            }
        }

        var groups: [LiveGroup] = []
        groups.reserveCapacity(sweep.groups.count)
        for (key, group) in sweep.groups where group.terminalParent == nil {
            if let childKeys = sweep.terminalChildren[key] {
                groups.append(terminalGroup(key: key, own: group, childKeys: childKeys, sweep: sweep, gpu: gpuDelta))
                continue
            }
            let list = (members[key] ?? []).sorted(by: Self.memberOrder)
            // Coalition gpu_time bu makinede çoğu canlı süreç için 0 kalıyor; AppUsage (süreç başına) farklarının toplamı ile
            // coalition farkından büyüğü alınır (ölü süreçlerin katkısı coalition'dan, canlıların ki AppUsage'tan).
            var usage = group.usage
            let gpuSum = group.pids.reduce(UInt64(0)) { $0 &+ (gpuDelta[$1] ?? 0) }
            usage.gpuNs = max(usage.gpuNs, gpuSum)
            groups.append(LiveGroup(key: key, usage: usage, processCount: group.pids.count, pids: group.pids,
                                    members: Array(list.prefix(Self.maxMembersPerGroup))))
        }
        return LiveSnapshot(groups: groups, elapsed: elapsed, totalProcessCount: sweep.groups.values.reduce(0) { $0 + $1.pids.count })
    }

    private static func memberOrder(_ a: LiveMember, _ b: LiveMember) -> Bool {
        a.usage.cpuNs != b.usage.cpuNs ? a.usage.cpuNs > b.usage.cpuNs : a.usage.footprint > b.usage.footprint
    }

    /// Terminal / IDE satırı: kendi süreçleri + tüm çalıştırılabilir kırılımı toplanır (coalition toplamı); üyeler çalıştırılabilire
    /// göre gruplanmış değerlerdir ("Warp › xcodebuild"). Kalan (kısa ömürlü süreçler) ayrı üye olarak gösterilir.
    private func terminalGroup(key: String, own: SweepResult.Group, childKeys: [String], sweep: SweepResult,
                               gpu: [pid_t: UInt64]) -> LiveGroup {
        func withGPU(_ g: SweepResult.Group) -> ResourceUsage {
            var u = g.usage
            u.gpuNs = max(u.gpuNs, g.pids.reduce(UInt64(0)) { $0 &+ (gpu[$1] ?? 0) })
            return u
        }
        var total = own.usage
        var pids = own.pids
        var members: [LiveMember] = []
        if !own.pids.isEmpty {
            let name = AppNaming.identity(forApp: key).name + " (uygulamanın kendisi)"
            members.append(LiveMember(pid: own.pids.min() ?? 0, name: name, usage: withGPU(own), pids: own.pids, childKey: key, path: key))
        }
        for ck in childKeys {
            guard let g = sweep.groups[ck], let parts = TerminalChildKey.split(ck) else { continue }
            total.add(g.usage)
            pids.append(contentsOf: g.pids)
            let residual = parts.child == TerminalChildKey.residual
            members.append(LiveMember(pid: g.pids.min() ?? 0, name: residual ? TerminalChildKey.residualLabel : AppNaming.executableName(parts.child),
                                      usage: withGPU(g), pids: g.pids, childKey: ck, path: residual ? nil : parts.child))
        }
        let gpuSum = pids.reduce(UInt64(0)) { $0 &+ (gpu[$1] ?? 0) }
        total.gpuNs = max(total.gpuNs, gpuSum)
        members.sort(by: Self.memberOrder)
        return LiveGroup(key: key, usage: total, processCount: pids.count, pids: pids, members: Array(members.prefix(Self.maxMembersPerGroup)))
    }
}
