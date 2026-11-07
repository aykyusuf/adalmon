import Foundation

/// "İşlemler" tablosundaki satır: uygulama grubu ya da (açılınca) üye süreç.
struct LiveRow: Identifiable, Hashable, Sendable {
    var id: String
    var key: String
    var name: String
    var pid: Int32?
    var processCount: Int
    var pids: [Int32]
    var category: ProcessCategory
    /// Uygulama paketi / çalıştırılabilir yol (Finder'da göster); sistem kovasında nil.
    var path: String?
    /// Makinenin tamamına göre yüzde (0-100): tüm çekirdeklerin ortalaması.
    var cpu: Double
    /// Ayak izi (bayt).
    var memory: Double
    /// GPU yüzdesi (tek motor üzerinden süre / duvar süresi).
    var gpu: Double
    /// Disk okuma + yazma (bayt/sn).
    var disk: Double
    /// Son 60 sn ortalama ağ (bayt/sn); üye süreçlerde yok.
    var network: Double
    /// Ortalama güç (W).
    var energy: Double

    /// Tüm (bizim) süreçleri askıda mı / verimlilik modunda mı.
    var isSuspended = false
    var isEfficient = false

    /// Aynı adlı başka bir satır varsa ayırt edici yer ipucu ("DerivedData", "/Applications"); yoksa nil.
    var pathHint: String?

    var isMember: Bool { pid != nil }

    struct Rates {
        var cpu = 0.0, gpu = 0.0, disk = 0.0, watts = 0.0
        init(usage: ResourceUsage, elapsed: Double, cores: Int) {
            guard elapsed > 0 else { return }
            cpu = Double(usage.cpuNs) / (elapsed * 1e9) * 100 / Double(max(1, cores))
            gpu = Double(usage.gpuNs) / (elapsed * 1e9) * 100
            disk = Double(usage.writeBytes &+ usage.readBytes) / elapsed
            watts = Double(usage.energyNj) / 1e9 / elapsed
        }
    }

    static func make(group: LiveGroup, elapsed: Double, cores: Int, name: String, category: ProcessCategory, networkBytes: Double) -> LiveRow {
        let r = Rates(usage: group.usage, elapsed: elapsed, cores: cores)
        return LiveRow(id: group.key, key: group.key, name: name, pid: nil, processCount: group.processCount, pids: group.pids,
                       category: category, path: group.key.hasPrefix("/") ? group.key : nil, cpu: r.cpu,
                       memory: Double(group.usage.footprint), gpu: r.gpu, disk: r.disk, network: networkBytes / 60, energy: r.watts)
    }

    static func make(member: LiveMember, group: LiveRow, elapsed: Double, cores: Int) -> LiveRow {
        let r = Rates(usage: member.usage, elapsed: elapsed, cores: cores)
        // Terminal üyeleri çalıştırılabilire göre gruplanır (kimlik: alt anahtar); tek süreç üyeleri pid ile.
        let id = member.childKey.map { "\(group.key)|member|\($0)" } ?? "\(group.key)|\(member.pid)"
        return LiveRow(id: id, key: group.key, name: member.name, pid: member.pid, processCount: member.pids.count,
                       pids: member.pids, category: group.category, path: member.path ?? group.path, cpu: r.cpu,
                       memory: Double(member.usage.footprint), gpu: r.gpu, disk: r.disk, network: 0, energy: r.watts)
    }
}
