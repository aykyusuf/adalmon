import Foundation

/// Terminal coalition'ının süreç başına bölünmesinin saf matematiği.
enum TerminalSplit {
    struct Parts: Sendable, Equatable {
        /// Terminalin kendi süreçleri (paketinin içinden çalışanlar).
        var own: ResourceUsage
        /// Çocuk anahtarı → toplanmış kullanım.
        var children: [String: ResourceUsage]
        /// Coalition toplamı − görülen süreçlerin toplamı: iki süpürme arasında doğup ölen süreçler.
        var residual: ResourceUsage
    }

    /// Kalan = coalition toplamı − (kendi + çocuklar), alan başına 0'da kırpılır. Bellek anlık değerdir: ölmüş süreçlerin
    /// ayak izi olmaz, bu yüzden kalanın belleği 0'dır. Süpürme süreç başına GPU süresi okumaz (coalition düzeyinde
    /// gelir), bu yüzden kalan GPU süresi terminalin kendisine verilir (ekranı çizen o).
    static func split(total: ResourceUsage, own: ResourceUsage, children: [String: ResourceUsage]) -> Parts {
        var seen = own
        for usage in children.values { seen.add(usage) }
        var residual = ResourceUsage(cpuNs: sub(total.cpuNs, seen.cpuNs), gpuNs: sub(total.gpuNs, seen.gpuNs),
                                     writeBytes: sub(total.writeBytes, seen.writeBytes), readBytes: sub(total.readBytes, seen.readBytes),
                                     energyNj: sub(total.energyNj, seen.energyNj), footprint: 0)
        var ownOut = own
        ownOut.gpuNs &+= residual.gpuNs
        residual.gpuNs = 0
        return Parts(own: ownOut, children: children, residual: residual)
    }

    private static func sub(_ a: UInt64, _ b: UInt64) -> UInt64 { a > b ? a - b : 0 }
}

/// Terminal üyesi süreçlerin aralık farkları. `ProcessDeltaTracker`dan farkı: iki süpürme arasında DOĞMUŞ ve hâlâ yaşayan süreç
/// ilk görüldüğünde 0 değil, birikimli değerinin tamamıdır (süreç aralığın içinde başladı). Önceden var olup ilk kez görülen
/// (okunamamış, taban çizgisi) süreç 0 verir.
struct TerminalChildTracker: Sendable {
    private var previous: [ProcessKey: ProcessCounters] = [:]
    private var lastSweepTicks: UInt64 = 0
    private var primed = false

    /// - Parameters:
    ///   - current: bu süpürmede okunan süreçler.
    ///   - sweepStartTicks: süpürmenin başladığı `mach_absolute_time` (süreç listesi okunmadan önce alınır).
    mutating func update(_ current: [ProcessKey: ProcessCounters], sweepStartTicks: UInt64, timebase: MachTimebase) -> [ProcessKey: ResourceUsage] {
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
            } else if primed && key.start >= lastSweepTicks {
                u.cpuNs = timebase.nanos(cur.cpuTicks)
                u.writeBytes = cur.bytesWritten
                u.readBytes = cur.bytesRead
                u.energyNj = cur.energyNj
            }
            out[key] = u
        }
        previous = current
        lastSweepTicks = sweepStartTicks
        primed = true
        return out
    }
}
