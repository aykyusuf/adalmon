import Darwin
import Foundation

/// Bir süpürmenin sonucu: uygulama anahtarı başına fark + üye pid'ler.
struct SweepResult: Sendable {
    struct Group: Sendable {
        var usage = ResourceUsage()
        var coalitions: [UInt64] = []
        var pids: [pid_t] = []
    }
    var groups: [String: Group] = [:]
    /// Süpürme zamanı (monotonik ns, uyku hariç `DispatchTime`).
    var uptimeNs: UInt64 = 0
    var usedCoalitionAPI = true

    var totalWriteBytes: UInt64 { groups.values.reduce(0) { $0 &+ $1.usage.writeBytes } }
}

/// Süreç listesi → coalition → uygulama anahtarı → fark. Durum (önceki sayaçlar, ad önbelleği) örnekte tutulur;
/// örnek tek bir kuyruğa/aktöre bağlı kullanılmalıdır (`@unchecked Sendable` değildir, sahibi yönetir).
final class ResourceSweeper {
    private var tracker = CoalitionDeltaTracker()
    private var processTracker = ProcessDeltaTracker()
    private var keyCache: [UInt64: String] = [:]
    private let timebase: MachTimebase
    /// Coalition API reddederse (sembol yok / saçma değer) süreç başına yedek yol kullanılır.
    private(set) var coalitionAPIWorks = true

    init(timebase: MachTimebase = .current) {
        self.timebase = timebase
    }

    func sweep() -> SweepResult {
        var result = SweepResult(uptimeNs: DispatchTime.now().uptimeNanoseconds)
        let pids = CoalitionAPI.listPIDs()
        var members: [UInt64: [pid_t]] = [:]
        for pid in pids {
            if let c = CoalitionAPI.coalitionID(of: pid) { members[c, default: []].append(pid) }
        }

        var perCoalition: [UInt64: ResourceUsage] = [:]
        if coalitionAPIWorks && CoalitionAPI.isCoalitionCounterAvailable {
            var raw: [UInt64: CoalitionCounters] = [:]
            var failures = 0
            for id in members.keys {
                if let c = CoalitionAPI.counters(of: id) { raw[id] = c } else { failures += 1 }
            }
            // Hiç coalition okunamadıysa API çalışmıyor sayılır (kalıcı yedeğe geç).
            if raw.isEmpty && failures > 0 { coalitionAPIWorks = false } else { perCoalition = tracker.update(raw, timebase: timebase) }
        } else {
            coalitionAPIWorks = false
        }
        if !coalitionAPIWorks {
            result.usedCoalitionAPI = false
            perCoalition = perProcessFallback(members)
        }

        for (cid, usage) in perCoalition {
            guard let pidsOfCoalition = members[cid] else { continue }
            let key = key(for: cid, members: pidsOfCoalition)
            var g = result.groups[key] ?? .init()
            g.usage.add(usage)
            g.coalitions.append(cid)
            g.pids.append(contentsOf: pidsOfCoalition)
            result.groups[key] = g
        }
        return result
    }

    /// Yedek: süreç başına rusage'i coalition'a toplar (yalnızca aynı kullanıcının süreçleri; ölü süreçler görünmez).
    private func perProcessFallback(_ members: [UInt64: [pid_t]]) -> [UInt64: ResourceUsage] {
        var current: [ProcessKey: ProcessCounters] = [:]
        var owner: [ProcessKey: UInt64] = [:]
        for (cid, pids) in members {
            for pid in pids {
                if let (k, c) = CoalitionAPI.processCounters(of: pid) { current[k] = c; owner[k] = cid }
            }
        }
        var out: [UInt64: ResourceUsage] = [:]
        for cid in members.keys { out[cid] = .zero }
        for (k, u) in processTracker.update(current, timebase: timebase) {
            if let cid = owner[k] { out[cid, default: .zero].add(u) }
        }
        return out
    }

    /// Coalition → uygulama anahtarı. Temsilci: sorumlu süreç (üyeyse), yoksa en küçük pid. Önbelleğe alınır;
    /// yol okunamıyorsa (süreç öldü) önbelleğe alınmaz.
    private func key(for coalition: UInt64, members: [pid_t]) -> String {
        if let k = keyCache[coalition] { return k }
        let sorted = members.sorted()
        if coalition == 1 || sorted.first == 1 {
            keyCache[coalition] = ResourceKeys.system
            return ResourceKeys.system
        }
        var rep = sorted.first
        for pid in sorted.prefix(4) {
            if let r = CoalitionAPI.responsiblePID(for: pid), sorted.contains(r) { rep = r; break }
        }
        guard let rep, let path = CoalitionAPI.path(of: rep) else { return ResourceKeys.unknown }
        let key = AppNaming.outermostApp(of: path)
        keyCache[coalition] = key
        return key
    }
}
