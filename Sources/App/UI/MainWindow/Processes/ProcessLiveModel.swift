import Foundation
import Observation

/// "Şu an" tablosundaki satır (uygulama grubu ya da üye süreç).
struct LiveRow: Identifiable, Hashable {
    var id: String
    var key: String
    var name: String
    var pid: Int32?
    var processCount: Int
    /// Çekirdek başına yüzde.
    var cpu: Double
    var memory: Double
    var gpu: Double
    var write: Double
    var energy: Double

    var isMember: Bool { pid != nil }

    static func make(group: LiveGroup, elapsed: Double, name: String) -> LiveRow {
        let r = Rates(usage: group.usage, elapsed: elapsed)
        return LiveRow(id: group.key, key: group.key, name: name, pid: nil, processCount: group.processCount,
                       cpu: r.cpu, memory: Double(group.usage.footprint), gpu: r.gpu, write: r.write, energy: r.watts)
    }

    static func make(member: LiveMember, key: String, elapsed: Double) -> LiveRow {
        let r = Rates(usage: member.usage, elapsed: elapsed)
        return LiveRow(id: "\(key)|\(member.pid)", key: key, name: member.name, pid: member.pid, processCount: 1,
                       cpu: r.cpu, memory: Double(member.usage.footprint), gpu: r.gpu, write: r.write, energy: r.watts)
    }

    struct Rates {
        var cpu = 0.0, gpu = 0.0, write = 0.0, watts = 0.0
        init(usage: ResourceUsage, elapsed: Double) {
            guard elapsed > 0 else { return }
            cpu = Double(usage.cpuNs) / (elapsed * 1e9) * 100
            gpu = Double(usage.gpuNs) / (elapsed * 1e9) * 100
            write = Double(usage.writeBytes) / elapsed
            watts = Double(usage.energyNj) / 1e9 / elapsed
        }
    }
}

/// "Şu an" sayfasının durumu. Örnekleme yalnızca sayfa (ve ana pencere) görünürken çalışır.
@MainActor @Observable
final class ProcessLiveModel {
    private(set) var rows: [LiveRow] = []
    private(set) var members: [String: [LiveRow]] = [:]
    /// İlk örnek yalnız taban çizgisidir; oranlar bir sonraki örnekten sonra gelir.
    private(set) var isMeasuring = true
    var expanded: Set<String> = []
    /// Tabloda gösterilen en çok satır (sıralamadan sonra).
    static let maxRows = 80

    @ObservationIgnored private var isSampling = false

    func run(service: ResourceService, model: AppModel) async {
        await service.live.reset()
        isMeasuring = true
        var first = true
        while !Task.isCancelled {
            if model.mainWindowVisible { await refresh(service: service) }
            let interval = first ? 1 : max(1, model.prefs.updateInterval)
            first = false
            try? await Task.sleep(for: .seconds(interval), tolerance: .milliseconds(interval * 150))
        }
    }

    /// Tek uçuşlu: üst üste biniyorsa atlanır.
    func refresh(service: ResourceService) async {
        guard !isSampling else { return }
        isSampling = true
        defer { isSampling = false }
        let snap = await service.live.sample(expanded: expanded)
        apply(snap)
    }

    func setExpanded(_ key: String, _ value: Bool, service: ResourceService) {
        if value { expanded.insert(key) } else { expanded.remove(key); members[key] = nil }
        Task { await refresh(service: service) }
    }

    private func apply(_ snap: LiveSnapshot) {
        isMeasuring = snap.elapsed == 0
        var out: [LiveRow] = []
        var mem: [String: [LiveRow]] = [:]
        out.reserveCapacity(snap.groups.count)
        for g in snap.groups {
            let row = LiveRow.make(group: g, elapsed: snap.elapsed, name: ResourceDisplay.name(g.key))
            // Etkinliği olmayan, küçük gruplar tabloyu şişirmesin.
            if row.memory < 1_000_000, row.cpu < 0.05, row.write < 1, row.gpu < 0.05 { continue }
            out.append(row)
            if !g.members.isEmpty { mem[g.key] = g.members.map { LiveRow.make(member: $0, key: g.key, elapsed: snap.elapsed) } }
        }
        rows = out
        members = mem
    }
}
