import Foundation

/// Geçmiş sorgularının ölçütü.
enum ResourceMetric: String, CaseIterable, Identifiable, Sendable {
    case cpu, gpu, memoryPeak, memoryAvg, diskWrite, energy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memoryPeak: "Bellek (tepe)"
        case .memoryAvg: "Bellek (ort.)"
        case .diskWrite: "Disk yazma"
        case .energy: "Enerji"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "display"
        case .memoryPeak, .memoryAvg: "memorychip"
        case .diskWrite: "internaldrive"
        case .energy: "bolt.fill"
        }
    }

    /// Bellek ölçütleri anlık (gauge) değerdir; diğerleri pencere boyunca toplanan sayaç farklarıdır.
    var isGauge: Bool { self == .memoryPeak || self == .memoryAvg }
}

/// Geçmiş penceresi (rawValue = saniye).
enum ResourceWindow: Int, CaseIterable, Identifiable, Sendable {
    case hour1 = 3_600, hours6 = 21_600, hours12 = 43_200, hours24 = 86_400, days7 = 604_800
    var id: Int { rawValue }
    var seconds: Int { rawValue }

    var title: String {
        switch self {
        case .hour1: "1 sa"
        case .hours6: "6 sa"
        case .hours12: "12 sa"
        case .hours24: "24 sa"
        case .days7: "7 gün"
        }
    }

    /// Seri grafiğinde kova genişliği (sn). 24 saatten eski veri saatliktir, bu yüzden 7 günde kova 1 saattir.
    var bucketSeconds: Int {
        switch self {
        case .hour1: 60
        case .hours6: 300
        case .hours12: 600
        case .hours24: 900
        case .days7: 3_600
        }
    }
}

/// Bir uygulama grubunun (coalition) bir aralıktaki kaynak kullanımı. Sayaçlar fark (delta), `footprint` anlık değerdir.
struct ResourceUsage: Sendable, Equatable {
    var cpuNs: UInt64 = 0
    var gpuNs: UInt64 = 0
    var writeBytes: UInt64 = 0
    var readBytes: UInt64 = 0
    var energyNj: UInt64 = 0
    var footprint: UInt64 = 0

    static let zero = ResourceUsage()

    var isZero: Bool { self == .zero }

    mutating func add(_ o: ResourceUsage) {
        cpuNs &+= o.cpuNs
        gpuNs &+= o.gpuNs
        writeBytes &+= o.writeBytes
        readBytes &+= o.readBytes
        energyNj &+= o.energyNj
        footprint &+= o.footprint
    }
}

/// Uygulama anahtarı + kullanım. Anahtar ağ sayfalarındakiyle aynıdır (`.app` yolu / çalıştırılabilir yol).
struct KeyedUsage: Sendable, Equatable {
    var key: String
    var usage: ResourceUsage
}

enum ResourceKeys {
    /// Dakikalık kayıtta ilk 15'e girmeyenlerin toplamı.
    static let other = "__other__"
    /// launchd altındaki bağımsız sistem süreçleri.
    static let system = "__system__"
    static let unknown = "__unknown__"

    static func isSpecial(_ key: String) -> Bool { key == other || key == system || key == unknown }
}

/// Geçmiş sorgusu sonucu: sıralı uygulama değeri.
struct ResourceRank: Sendable, Equatable, Identifiable {
    var app: String
    /// cpu/gpu: ns toplamı; diskWrite: bayt toplamı; energy: nJ toplamı; bellek: bayt.
    var value: Double
    var id: String { app }
}

struct ResourceSeriesPoint: Sendable, Equatable, Identifiable {
    var ts: Int
    var value: Double
    var id: Int { ts }
}

struct DiskFreePoint: Sendable, Equatable, Identifiable {
    var ts: Int
    var freeBytes: UInt64
    var id: Int { ts }
}

struct FolderSnapshotEntry: Sendable, Equatable {
    var path: String
    var depth: Int
    var bytes: UInt64
}

struct FolderGrowth: Sendable, Equatable, Identifiable {
    var path: String
    var depth: Int
    var currentBytes: UInt64
    /// Pencere başındaki (ya da en eski) anlık görüntüye göre değişim; negatif = küçüldü.
    var growthBytes: Int64
    var id: String { path }
}

/// "Uygulama geçmişi" tablosunun satırı: pencere boyunca toplamlar (bellek: tepe).
struct AppHistoryRow: Sendable, Equatable, Identifiable {
    var app: String
    var cpuNs: Double
    var gpuNs: Double
    var writeBytes: Double
    var energyNj: Double
    var memoryPeak: Double
    var networkBytes: Double
    var id: String { app }

    var hasActivity: Bool { cpuNs > 0 || gpuNs > 0 || writeBytes > 0 || energyNj > 0 || memoryPeak > 0 || networkBytes > 0 }
}

/// Tüm sistemin bir kovadaki toplamı (Performans sekmesi, kayıtlı geçmiş).
struct ResourceTotalPoint: Sendable, Equatable, Identifiable {
    var ts: Int
    var cpuNs: Double = 0
    var gpuNs: Double = 0
    var writeBytes: Double = 0
    var readBytes: Double = 0
    /// Uygulama ayak izi toplamı (dakikalık kayıttaki ilk 15 + diğer); sistemin "kullanılan" belleğinden küçüktür.
    var footprint: Double = 0
    var id: Int { ts }
}
