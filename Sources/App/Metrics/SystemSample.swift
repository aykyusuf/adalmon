import Foundation

/// Bir ölçüm anının sayıları (grafik geçmişi için). Yalnızca sayı tutar; `SystemSnapshot`'ın geri kalanı saklanmaz.
struct SystemSample: Sendable, Equatable {
    var time: Date
    /// 0...1
    var cpu: Double
    /// 0...1 (kullanılan / toplam)
    var memory: Double
    /// 0...1
    var gpu: Double
    /// Bayt/sn
    var diskRead: Double
    var diskWrite: Double
    var down: Double
    var up: Double

    init(time: Date, cpu: Double, memory: Double, gpu: Double, diskRead: Double, diskWrite: Double, down: Double, up: Double) {
        self.time = time
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.diskRead = diskRead
        self.diskWrite = diskWrite
        self.down = down
        self.up = up
    }

    init(_ s: SystemSnapshot) {
        self.init(time: s.timestamp, cpu: s.cpu.total, memory: s.memory.usedFraction, gpu: s.gpu?.displayLoad ?? 0,
                  diskRead: s.disk.readBytesPerSecond, diskWrite: s.disk.writeBytesPerSecond,
                  down: s.network.downloadBytesPerSecond, up: s.network.uploadBytesPerSecond)
    }

    /// Spark çizgileri için tek sayı (disk/ağ: okuma+yazma, indirme+yükleme toplamı).
    func value(_ metric: PerformanceMetric) -> Double {
        switch metric {
        case .cpu: cpu
        case .memory: memory
        case .gpu: gpu
        case .disk: diskRead + diskWrite
        case .network: down + up
        }
    }
}
