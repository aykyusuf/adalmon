import Darwin
import Foundation

struct LiveMember: Sendable, Equatable, Identifiable {
    var pid: Int32
    var name: String
    var usage: ResourceUsage
    var id: Int32 { pid }
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
                guard let group = sweep.groups[key] else { continue }
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
        for (key, group) in sweep.groups {
            let list = (members[key] ?? []).sorted {
                $0.usage.cpuNs != $1.usage.cpuNs ? $0.usage.cpuNs > $1.usage.cpuNs : $0.usage.footprint > $1.usage.footprint
            }
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
}
