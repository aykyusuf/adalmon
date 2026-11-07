import Foundation

/// "İşlemler" tablosunun sayısal sütunları (ad sütunu ayrıdır).
enum ProcessColumn: String, CaseIterable, Identifiable, Hashable, Sendable {
    case name, cpu, memory, disk, network, gpu, energy

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
        }
    }

    /// Sütunun varsayılan sıralama yönü: ad artan, sayılar azalan.
    var defaultAscending: Bool { self == .name }
}
