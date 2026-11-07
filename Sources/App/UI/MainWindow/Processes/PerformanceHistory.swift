import Foundation

/// Canlı Performans grafikleri için son örnekler (sayfa görünürken toplanır; en çok `capacity` nokta).
struct PerformanceHistory: Equatable, Sendable {
    static let capacity = 60

    /// 0...1
    var cpu: [Double] = []
    var memory: [Double] = []
    var gpu: [Double] = []
    /// Bayt/sn
    var diskRead: [Double] = []
    var diskWrite: [Double] = []
    var down: [Double] = []
    var up: [Double] = []
    private(set) var lastTimestamp: Date?

    var count: Int { cpu.count }

    /// Aynı ölçüm (zaman damgası) iki kez eklenmez.
    mutating func append(_ s: SystemSnapshot) {
        guard s.timestamp != lastTimestamp else { return }
        lastTimestamp = s.timestamp
        Self.push(&cpu, s.cpu.total)
        Self.push(&memory, s.memory.usedFraction)
        Self.push(&gpu, s.gpu?.displayLoad ?? 0)
        Self.push(&diskRead, s.disk.readBytesPerSecond)
        Self.push(&diskWrite, s.disk.writeBytesPerSecond)
        Self.push(&down, s.network.downloadBytesPerSecond)
        Self.push(&up, s.network.uploadBytesPerSecond)
    }

    /// Sayfa açılırken `AppModel`'in zaten tuttuğu son 60 örnekle başlat (grafik boş açılmasın).
    mutating func seed(cpu: [Double], memory: [Double], gpu: [Double], down: [Double], up: [Double]) {
        guard count == 0 else { return }
        self.cpu = Array(cpu.suffix(Self.capacity))
        self.memory = Array(memory.suffix(Self.capacity))
        self.gpu = Array(gpu.suffix(Self.capacity))
        self.down = Array(down.suffix(Self.capacity))
        self.up = Array(up.suffix(Self.capacity))
        let n = self.cpu.count
        diskRead = Array(repeating: 0, count: n)
        diskWrite = Array(repeating: 0, count: n)
        // Hepsi aynı uzunlukta olmalı (grafikler indeksle eşler).
        self.memory = Self.fit(self.memory, n)
        self.gpu = Self.fit(self.gpu, n)
        self.down = Self.fit(self.down, n)
        self.up = Self.fit(self.up, n)
    }

    private static func fit(_ a: [Double], _ n: Int) -> [Double] {
        a.count >= n ? Array(a.suffix(n)) : Array(repeating: 0, count: n - a.count) + a
    }

    private static func push(_ a: inout [Double], _ v: Double) {
        a.append(v)
        if a.count > capacity { a.removeFirst(a.count - capacity) }
    }

    func values(_ metric: PerformanceMetric) -> [Double] {
        switch metric {
        case .cpu: cpu
        case .memory: memory
        case .gpu: gpu
        case .disk: zip(diskRead, diskWrite).map { $0 + $1 }
        case .network: zip(down, up).map { $0 + $1 }
        }
    }
}
