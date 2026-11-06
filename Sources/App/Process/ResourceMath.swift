import Darwin
import Foundation

/// Mach saat birimi → nanosaniye (Apple Silicon'da 125/3). Tutarlı büyük değerlerde taşmasın diye bölüp çarpar.
struct MachTimebase: Sendable, Equatable {
    var numer: UInt32
    var denom: UInt32

    static let current: MachTimebase = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return MachTimebase(numer: info.numer, denom: max(1, info.denom))
    }()

    func nanos(_ ticks: UInt64) -> UInt64 {
        let n = UInt64(numer), d = UInt64(max(1, denom))
        return (ticks / d) &* n &+ (ticks % d) &* n / d
    }
}

/// `coalition_info_resource_usage` çıktısından kullanılan ham (birikimli) sayaçlar.
struct CoalitionCounters: Sendable, Equatable {
    var tasksStarted: UInt64 = 0
    var tasksExited: UInt64 = 0
    var cpuTicks: UInt64 = 0
    var bytesRead: UInt64 = 0
    var bytesWritten: UInt64 = 0
    var gpuNs: UInt64 = 0
    var energyNj: UInt64 = 0
    var footprint: UInt64 = 0
}

enum CounterMath {
    /// Birikimli sayaç farkı; sayaç geri giderse (süreç/coalition yeniden kullanımı, sıfırlama) 0.
    static func delta(_ previous: UInt64, _ current: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }
}

/// Coalition başına birikimli sayaçlardan aralık farkı üretir. Durum yalnızca bellektedir.
/// - İlk süpürme yalnızca taban çizgisidir (delta 0).
/// - Sonradan görülen yeni coalition aralık içinde doğmuştur: tüm birikimli değeri delta olur
///   (ölü kısa ömürlü süreçler dahil).
/// - `tasksStarted` ya da CPU geri giderse coalition numarası yeniden kullanılmış / sıfırlanmış demektir: o tur delta 0.
struct CoalitionDeltaTracker: Sendable {
    private var previous: [UInt64: CoalitionCounters] = [:]
    private var lastSeen: [UInt64: Int] = [:]
    private var sweepNumber = 0
    private var primed = false
    /// Bu kadar süpürme görünmeyen coalition unutulur.
    static let forgetAfter = 5

    var isPrimed: Bool { primed }

    mutating func update(_ current: [UInt64: CoalitionCounters], timebase: MachTimebase) -> [UInt64: ResourceUsage] {
        sweepNumber += 1
        var out: [UInt64: ResourceUsage] = [:]
        out.reserveCapacity(current.count)
        for (id, cur) in current {
            var u = ResourceUsage()
            u.footprint = cur.footprint
            if let prev = previous[id] {
                let reset = cur.tasksStarted < prev.tasksStarted || cur.cpuTicks < prev.cpuTicks
                if !reset {
                    u.cpuNs = timebase.nanos(CounterMath.delta(prev.cpuTicks, cur.cpuTicks))
                    u.gpuNs = CounterMath.delta(prev.gpuNs, cur.gpuNs)
                    u.writeBytes = CounterMath.delta(prev.bytesWritten, cur.bytesWritten)
                    u.readBytes = CounterMath.delta(prev.bytesRead, cur.bytesRead)
                    u.energyNj = CounterMath.delta(prev.energyNj, cur.energyNj)
                }
            } else if primed {
                u.cpuNs = timebase.nanos(cur.cpuTicks)
                u.gpuNs = cur.gpuNs
                u.writeBytes = cur.bytesWritten
                u.readBytes = cur.bytesRead
                u.energyNj = cur.energyNj
            }
            out[id] = u
            previous[id] = cur
            lastSeen[id] = sweepNumber
        }
        if sweepNumber % 4 == 0 {
            let cutoff = sweepNumber - Self.forgetAfter
            for (id, seen) in lastSeen where seen < cutoff {
                lastSeen[id] = nil
                previous[id] = nil
            }
        }
        primed = true
        return out
    }
}

/// Süreç başına (pid + başlangıç zamanı) birikimli sayaçlar; coalition API yoksa yedek yol ve canlı alt süreç satırları.
struct ProcessCounters: Sendable, Equatable {
    var cpuTicks: UInt64 = 0
    var bytesWritten: UInt64 = 0
    var bytesRead: UInt64 = 0
    var energyNj: UInt64 = 0
    var footprint: UInt64 = 0
    var gpuNs: UInt64 = 0
}

struct ProcessKey: Hashable, Sendable {
    var pid: Int32
    /// `ri_proc_start_abstime`: pid yeniden kullanımını ayırt eder.
    var start: UInt64
}

struct ProcessDeltaTracker: Sendable {
    private var previous: [ProcessKey: ProcessCounters] = [:]
    private var primed = false

    /// - Returns: süreç başına fark. Yeni (ya da pid'i yeniden kullanılmış) anahtarda ilk örnek 0 verir, ilk tur taban çizgisidir.
    mutating func update(_ current: [ProcessKey: ProcessCounters], timebase: MachTimebase) -> [ProcessKey: ResourceUsage] {
        var out: [ProcessKey: ResourceUsage] = [:]
        out.reserveCapacity(current.count)
        for (key, cur) in current {
            var u = ResourceUsage()
            u.footprint = cur.footprint
            if let prev = previous[key] {
                u.cpuNs = timebase.nanos(CounterMath.delta(prev.cpuTicks, cur.cpuTicks))
                u.writeBytes = CounterMath.delta(prev.bytesWritten, cur.bytesWritten)
                u.readBytes = CounterMath.delta(prev.bytesRead, cur.bytesRead)
                u.energyNj = CounterMath.delta(prev.energyNj, cur.energyNj)
                u.gpuNs = CounterMath.delta(prev.gpuNs, cur.gpuNs)
            }
            out[key] = u
        }
        previous = current
        primed = true
        return out
    }
}

/// Dakikalık kayıt için ölçüt başına ilk N'in birleşimi + kalanların `__other__` toplamı.
enum TopNUnion {
    static let metricCount = 5

    /// Aynı anahtarlı girdileri birleştirir (aynı uygulamanın birden çok coalition'ı).
    static func merge(_ items: [KeyedUsage]) -> [KeyedUsage] {
        var byKey: [String: ResourceUsage] = [:]
        for i in items { byKey[i.key, default: .zero].add(i.usage) }
        return byKey.map { KeyedUsage(key: $0.key, usage: $0.value) }.sorted { $0.key < $1.key }
    }

    /// Ölçütler: cpu, gpu, disk yazma, enerji, bellek. Değeri 0 olan girdi o ölçütte sayılmaz.
    static func select(_ items: [KeyedUsage], perMetric n: Int = 15) -> [KeyedUsage] {
        let merged = merge(items)
        let paths: [KeyPath<ResourceUsage, UInt64>] = [\.cpuNs, \.gpuNs, \.writeBytes, \.energyNj, \.footprint]
        var chosen = Set<String>()
        for path in paths {
            let ranked = merged.filter { $0.usage[keyPath: path] > 0 }
                .sorted {
                    let a = $0.usage[keyPath: path], b = $1.usage[keyPath: path]
                    return a != b ? a > b : $0.key < $1.key
                }
            for item in ranked.prefix(n) { chosen.insert(item.key) }
        }
        var result: [KeyedUsage] = []
        var other = ResourceUsage()
        for item in merged {
            if chosen.contains(item.key) { result.append(item) } else { other.add(item.usage) }
        }
        if !other.isZero { result.append(KeyedUsage(key: ResourceKeys.other, usage: other)) }
        return result
    }
}

/// Klasör büyüme listesi: üst klasör, torunlarından biri büyümenin ≥%50'sini taşıyorsa elenir (aynı bayt iki kez görünmesin).
enum FolderGrowthCollapse {
    static func collapse(_ items: [FolderGrowth]) -> [FolderGrowth] {
        func isAncestor(_ a: String, of b: String) -> Bool { b.count > a.count && b.hasPrefix(a.hasSuffix("/") ? a : a + "/") }
        return items.filter { parent in
            guard parent.growthBytes > 0 else { return true }
            return !items.contains { child in
                isAncestor(parent.path, of: child.path) && child.growthBytes > 0 && child.growthBytes * 2 >= parent.growthBytes
            }
        }
    }
}

/// Saatlik klasör taramasını atlama kararı (pil): kullanıcı "Tara" ile istemedikçe.
enum ScanPolicy {
    static let minimumBatteryPercent = 20

    /// - Returns: atlanma nedeni; nil = taranabilir.
    static func skipReason(lowPowerMode: Bool, onBattery: Bool, batteryPercent: Int?) -> String? {
        if lowPowerMode { return "Düşük Güç Modu açık" }
        if onBattery, let p = batteryPercent, p < minimumBatteryPercent { return "Pil %\(p) (%\(minimumBatteryPercent) altı)" }
        return nil
    }

    /// Yazma etkinliği çok düşükse (son taramadan beri) ve son tarama taze ise tarama atlanır; klasörler büyüyemez.
    static func canSkipAsIdle(bytesWrittenSinceScan: UInt64, secondsSinceScan: Double) -> Bool {
        bytesWrittenSinceScan < 20_000_000 && secondsSinceScan < 6 * 3_600
    }
}
