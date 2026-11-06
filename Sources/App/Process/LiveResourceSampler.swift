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
    var members: [LiveMember]
    var id: String { key }
}

struct LiveSnapshot: Sendable, Equatable {
    var groups: [LiveGroup] = []
    /// Önceki örnekten beri geçen süre (sn); ilk örnekte 0 (taban çizgisi, oranlar anlamsız).
    var elapsed: Double = 0
}

/// "Süreçler > Şu an" sayfası için canlı örnekleyici: yalnızca sayfa görünürken çağrılır. Arka plan örnekleyicisinden bağımsız
/// durum tutar (kendi önceki sayaçları). Coalition bazlı grup değerleri + üye süreç kırılımı (rusage + AppUsage GPU).
actor LiveResourceSampler {
    private let sweeper = ResourceSweeper()
    private var memberTracker = ProcessDeltaTracker()
    private var lastNs: UInt64 = 0
    private var names: [ProcessKey: String] = [:]
    private let timebase = MachTimebase.current
    static let maxMembersPerGroup = 25

    /// Sayfa yeniden göründüğünde eski taban çizgisi atılır (uzun boşluk).
    func reset() {
        lastNs = 0
        memberTracker = ProcessDeltaTracker()
        names = [:]
    }

    /// - Parameter expanded: üye süreç kırılımı istenen uygulama anahtarları. Yalnızca bunlar için süreç başına rusage /
    ///   yol okunur ve (en az biri varsa) GPU istemci listesi alınır; açık satır yoksa yalnızca coalition süpürmesi çalışır.
    func sample(expanded: Set<String> = []) -> LiveSnapshot {
        let sweep = sweeper.sweep()
        let elapsed = lastNs == 0 ? 0 : Double(sweep.uptimeNs &- lastNs) / 1e9
        lastNs = sweep.uptimeNs

        var members: [String: [LiveMember]] = [:]
        if expanded.isEmpty {
            memberTracker = ProcessDeltaTracker()
            names = [:]
        } else {
            let gpu = GPUClientUsage.snapshot()
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
            groups.append(LiveGroup(key: key, usage: group.usage, processCount: group.pids.count,
                                    members: Array(list.prefix(Self.maxMembersPerGroup))))
        }
        return LiveSnapshot(groups: groups, elapsed: elapsed)
    }
}
