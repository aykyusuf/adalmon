import Foundation

/// Sütun başlıklarında gösterilen sistem toplamları ("CPU %23", "Bellek %61" …).
struct ProcessTotals: Equatable, Sendable {
    /// 0-100.
    var cpu = 0.0
    /// 0-1.
    var memoryFraction = 0.0
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    /// Bayt/sn (okuma + yazma).
    var disk = 0.0
    /// Bayt/sn (indirme + yükleme).
    var network = 0.0
    /// 0-100.
    var gpu = 0.0
    /// W.
    var energy = 0.0

    init() {}

    init(snapshot: SystemSnapshot?, rows: [LiveRow]) {
        energy = rows.reduce(0) { $0 + $1.energy }
        if let s = snapshot {
            cpu = s.cpu.total * 100
            memoryFraction = s.memory.usedFraction
            memoryUsed = s.memory.usedBytes
            memoryTotal = s.memory.totalBytes
            disk = s.disk.readBytesPerSecond + s.disk.writeBytesPerSecond
            network = s.network.downloadBytesPerSecond + s.network.uploadBytesPerSecond
            gpu = (s.gpu?.displayLoad ?? 0) * 100
        } else {
            cpu = min(100, rows.reduce(0) { $0 + $1.cpu })
            disk = rows.reduce(0) { $0 + $1.disk }
            gpu = min(100, rows.reduce(0) { $0 + $1.gpu })
        }
    }
}
