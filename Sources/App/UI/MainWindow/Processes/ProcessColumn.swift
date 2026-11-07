import Foundation

/// "İşlemler" tablosunun sütunları. Ad her zaman; ısı haritalı ölçüt sütunları her zaman; bilgi sütunları
/// (Tür, Süreç, PID) yalnızca pencere genişken eklenir (ucuz: `LiveRow`'da zaten olan veriler).
enum ProcessColumn: String, CaseIterable, Identifiable, Hashable, Sendable {
    case name, cpu, memory, disk, network, gpu, energy
    case category, processCount, pid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Ad"
        case .cpu: "CPU"
        case .memory: "Bellek"
        case .disk: "Disk"
        case .network: "Ağ"
        case .gpu: "GPU"
        case .energy: "Enerji"
        case .category: "Tür"
        case .processCount: "Süreç"
        case .pid: "PID"
        }
    }

    /// Isı haritalı, sistem toplamı gösteren ölçüt sütunu mu.
    var isMetric: Bool {
        switch self {
        case .cpu, .memory, .disk, .network, .gpu, .energy: true
        case .name, .category, .processCount, .pid: false
        }
    }

    /// Satırın bu sütundaki sıralama değeri.
    func value(of row: LiveRow) -> Double {
        switch self {
        case .name: 0
        case .cpu: row.cpu
        case .memory: row.memory
        case .disk: row.disk
        case .network: row.network
        case .gpu: row.gpu
        case .energy: row.energy
        case .category: Double(row.category.rawValue)
        case .processCount: Double(row.processCount)
        case .pid: Double(row.pid ?? 0)
        }
    }

    /// Sütunun varsayılan sıralama yönü: ad ve tür artan, sayılar azalan.
    var defaultAscending: Bool { self == .name || self == .category }
}
