import Foundation

/// Tek bir örnekleme anındaki sistem metrikleri. Oranlar (yüzde, byte/s) iki örnek arasındaki farktan hesaplanır.
struct SystemSnapshot: Sendable, Equatable {
    var timestamp: Date
    var cpu: CPUStats
    var memory: MemoryStats
    var disk: DiskStats
    var network: InterfaceStats
    /// GPU okunamazsa nil.
    var gpu: GPUStats?
    /// Sıcaklıklar okunamazsa nil.
    var temperature: TemperatureStats? = nil
}

/// Santigrat derece. Okunamayan alan nil.
struct TemperatureStats: Sendable, Equatable {
    /// CPU çekirdek sensörlerinin ortalaması.
    var cpu: Double?
    var cpuMax: Double?
    var gpu: Double?
    var ssd: Double?
    var battery: Double?
    /// Ham sensör adı → değer (ayrıntı görünümü için).
    var sensors: [String: Double] = [:]
}

struct CPUStats: Sendable, Equatable {
    /// 0...1 toplam kullanım (user + system + nice).
    var total: Double
    var user: Double
    var system: Double
    /// Çekirdek başına 0...1.
    var perCore: [Double]
    /// Performance çekirdek sayısı / Efficiency çekirdek sayısı (hw.perflevel0/1.logicalcpu). Okunamazsa 0.
    var performanceCores: Int
    var efficiencyCores: Int
    /// 1, 5, 15 dakika load average.
    var loadAverage: [Double]
}

struct MemoryStats: Sendable, Equatable {
    var totalBytes: UInt64
    /// active + inactive + speculative + wired + compressed − purgeable − external
    var usedBytes: UInt64
    var appBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var cachedBytes: UInt64
    var swapUsedBytes: UInt64
    var swapTotalBytes: UInt64
    var pressure: MemoryPressure
    var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

enum MemoryPressure: Int, Sendable, Equatable {
    case normal = 1, warning = 2, critical = 4
}

struct DiskStats: Sendable, Equatable {
    /// Ana (Data) volume.
    var totalBytes: UInt64
    /// statfs ile saf boş alan.
    var freeBytes: UInt64
    /// volumeAvailableCapacityForImportantUsage (purgeable dahil).
    var availableBytes: UInt64
    var readBytesPerSecond: Double
    var writeBytesPerSecond: Double
    var usedFraction: Double { totalBytes == 0 ? 0 : 1 - Double(availableBytes) / Double(totalBytes) }
}

struct InterfaceStats: Sendable, Equatable {
    /// Birincil fiziksel arayüz adı (en0, en5 …). utun/lo/awdl/llw hariç.
    var primaryInterface: String
    var downloadBytesPerSecond: Double
    var uploadBytesPerSecond: Double
    /// Fiziksel arayüzlerin (utun/lo/awdl/llw/bridge hariç) kümülatif 64-bit sayaçları, arayüz adına göre.
    var cumulativeIn: [String: UInt64]
    var cumulativeOut: [String: UInt64]
}

struct GPUStats: Sendable, Equatable {
    /// 0...1 "Device Utilization %".
    var utilization: Double
    var rendererUtilization: Double?
    var tilerUtilization: Double?
    var memoryUsedBytes: UInt64?
    /// 0...1 frekans ağırlıklı yük (IOReport GPUPH): Σ(süre × frekans) / en yüksek frekans. Okunamazsa nil.
    var load: Double? = nil
    /// 0...1 GPU'nun OFF dışındaki durumlarda geçirdiği süre (donanım aktif süresi).
    var activeResidency: Double? = nil
    /// Aktif sürede ortalama GPU frekansı (MHz).
    var frequencyMHz: Double? = nil
    /// Bu çipin en yüksek GPU frekansı (MHz).
    var maxFrequencyMHz: Double? = nil

    /// Gösterilecek yük: frekans ağırlıklı yük varsa o, yoksa meşgul süre.
    var displayLoad: Double { load ?? utilization }
}

/// Sampler sözleşmesi. Ana thread dışında, seri bir kuyruktan saniyede bir çağrılır.
/// İlk çağrıda oranlar 0 döner (önceki örnek yok).
protocol MetricsSampling: AnyObject {
    func sample() -> SystemSnapshot
}
