import Darwin
import Foundation

/// Bir süpürmenin sonucu: uygulama anahtarı başına fark + üye pid'ler.
struct SweepResult: Sendable {
    struct Group: Sendable {
        var usage = ResourceUsage()
        var coalitions: [UInt64] = []
        var pids: [pid_t] = []
        /// Terminal alt anahtarlarında (süreç başına bölünmüş) üst terminalin anahtarı.
        var terminalParent: String?
    }
    var groups: [String: Group] = [:]
    /// Süreç başına bölünmüş terminal anahtarı → alt anahtarları (çalıştırılabilir başına + kısa ömürlü kalan).
    /// Terminalin kendi anahtarı yalnızca kendi süreçlerini taşır; alt anahtarlarla toplamı coalition toplamıdır.
    var terminalChildren: [String: [String]] = [:]
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
    private var terminalTracker = TerminalChildTracker()
    private var keyCache: [UInt64: String] = [:]
    /// Anahtarı bilinen terminal / IDE coalition'ları.
    private var terminalIDs = Set<UInt64>()
    /// Süreç → alt anahtar (terminalin kendisi ya da `"<terminal>|<çalıştırılabilir>"`); yaşayan süreçler için tutulur.
    private var childKeyCache: [ProcessKey: String] = [:]
    private let timebase: MachTimebase
    /// Terminal / IDE coalition'larını süreç başına böl (bkz. `TerminalApps`). Kapalıyken eski davranış (ölçüm karşılaştırması).
    let splitsTerminals: Bool
    /// Coalition API reddederse (sembol yok / saçma değer) süreç başına yedek yol kullanılır.
    private(set) var coalitionAPIWorks = true

    init(timebase: MachTimebase = .current, splitsTerminals: Bool = true) {
        self.timebase = timebase
        self.splitsTerminals = splitsTerminals
    }

    func sweep() -> SweepResult {
        var result = SweepResult(uptimeNs: DispatchTime.now().uptimeNanoseconds)
        let startTicks = mach_absolute_time()
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

        var terminals: [PendingTerminal] = []
        for (cid, usage) in perCoalition {
            guard let pidsOfCoalition = members[cid] else { continue }
            let key = key(for: cid, members: pidsOfCoalition)
            if splitsTerminals && terminalIDs.contains(cid) {
                terminals.append(PendingTerminal(coalition: cid, key: key, usage: usage, pids: pidsOfCoalition))
                continue
            }
            var g = result.groups[key] ?? .init()
            g.usage.add(usage)
            g.coalitions.append(cid)
            g.pids.append(contentsOf: pidsOfCoalition)
            result.groups[key] = g
        }
        if splitsTerminals { splitTerminals(terminals, startTicks: startTicks, into: &result) }
        return result
    }

    private struct PendingTerminal {
        var coalition: UInt64
        var key: String
        var usage: ResourceUsage
        var pids: [pid_t]
    }

    /// Terminal coalition'larını süreç başına böler: süreç başına rusage (yalnızca bu coalition'ların ~onlarca süreci) →
    /// çalıştırılabilir başına toplam; coalition toplamından görülenler çıkınca kalan "kısa ömürlü süreçler"dir.
    private func splitTerminals(_ terminals: [PendingTerminal], startTicks: UInt64, into result: inout SweepResult) {
        var current: [ProcessKey: ProcessCounters] = [:]
        var owner: [ProcessKey: (index: Int, pid: pid_t, childKey: String)] = [:]
        var unreadable: [Int: [pid_t]] = [:]
        var liveKeys = Set<ProcessKey>()
        for (i, t) in terminals.enumerated() {
            for pid in t.pids {
                guard let found = CoalitionAPI.processCounters(of: pid) else {
                    unreadable[i, default: []].append(pid)
                    continue
                }
                guard let childKey = childKey(for: found.key, pid: pid, terminal: t.key) else {
                    unreadable[i, default: []].append(pid)
                    continue
                }
                current[found.key] = found.counters
                owner[found.key] = (i, pid, childKey)
                liveKeys.insert(found.key)
            }
        }
        childKeyCache = childKeyCache.filter { liveKeys.contains($0.key) }
        let deltas = terminalTracker.update(current, sweepStartTicks: startTicks, timebase: timebase)

        for (i, t) in terminals.enumerated() {
            var own = ResourceUsage()
            var ownPids = unreadable[i] ?? []
            var children: [String: ResourceUsage] = [:]
            var childPids: [String: [pid_t]] = [:]
            for (pk, usage) in deltas {
                guard let o = owner[pk], o.index == i else { continue }
                if o.childKey == t.key {
                    own.add(usage)
                    ownPids.append(o.pid)
                } else {
                    children[o.childKey, default: .zero].add(usage)
                    childPids[o.childKey, default: []].append(o.pid)
                }
            }
            let parts = TerminalSplit.split(total: t.usage, own: own, children: children)
            var ownGroup = result.groups[t.key] ?? .init()
            ownGroup.usage.add(parts.own)
            ownGroup.coalitions.append(t.coalition)
            ownGroup.pids.append(contentsOf: ownPids)
            result.groups[t.key] = ownGroup
            for (ck, usage) in parts.children {
                var g = result.groups[ck] ?? .init()
                g.usage.add(usage)
                g.coalitions.append(t.coalition)
                g.pids.append(contentsOf: childPids[ck] ?? [])
                g.terminalParent = t.key
                result.groups[ck] = g
                if !(result.terminalChildren[t.key]?.contains(ck) ?? false) { result.terminalChildren[t.key, default: []].append(ck) }
            }
            if result.terminalChildren[t.key] == nil { result.terminalChildren[t.key] = [] }
            if !parts.residual.isZero {
                let rk = TerminalChildKey.residualKey(terminal: t.key)
                var g = result.groups[rk] ?? .init()
                g.usage.add(parts.residual)
                g.coalitions.append(t.coalition)
                g.terminalParent = t.key
                result.groups[rk] = g
                if !(result.terminalChildren[t.key]?.contains(rk) ?? false) { result.terminalChildren[t.key, default: []].append(rk) }
            }
        }
    }

    /// Süreç → alt anahtar. Terminal paketinin içinden çalışan (terminalin kendisi, yardımcıları) terminal anahtarına yazılır.
    /// Yol okunamıyorsa (süreç öldü) nil; önbelleğe alınmaz.
    private func childKey(for process: ProcessKey, pid: pid_t, terminal: String) -> String? {
        if let k = childKeyCache[process] { return k }
        guard let path = CoalitionAPI.path(of: pid) else { return nil }
        let k = path.hasPrefix(terminal + "/") ? terminal : TerminalChildKey.make(terminal: terminal, child: path)
        childKeyCache[process] = k
        return k
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
        if TerminalApps.isTerminal(key: key) { terminalIDs.insert(coalition) }
        return key
    }
}
