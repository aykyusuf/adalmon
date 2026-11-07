import Foundation

/// "Uygulama geçmişi" tablosunun sütunları.
enum HistoryColumn: String, CaseIterable, Identifiable, Hashable, Sendable {
    case name, cpu, gpu, disk, network, energy, memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Ad"
        case .cpu: "CPU süresi"
        case .gpu: "GPU süresi"
        case .disk: "Disk yazma"
        case .network: "Ağ"
        case .energy: "Enerji"
        case .memory: "Bellek (tepe)"
        }
    }

    static let numeric: [HistoryColumn] = [.cpu, .gpu, .disk, .network, .energy, .memory]

    var width: CGFloat {
        switch self {
        case .name: 190
        case .cpu, .gpu: 86
        case .disk, .network: 84
        case .energy: 84
        case .memory: 94
        }
    }

    func value(of row: AppHistoryRow) -> Double {
        switch self {
        case .name: 0
        case .cpu: row.cpuNs
        case .gpu: row.gpuNs
        case .disk: row.writeBytes
        case .network: row.networkBytes
        case .energy: row.energyNj
        case .memory: row.memoryPeak
        }
    }

    func text(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        switch self {
        case .name: return ""
        case .cpu, .gpu:
            // 10 dakikadan uzun sürelerde saniye atılır (sütuna sığsın).
            let seconds = value / 1e9
            return ResourceFormat.duration(seconds: seconds >= 600 ? (seconds / 60).rounded() * 60 : seconds)
        case .disk, .network, .memory: return ResourceFormat.bytes(value)
        case .energy: return ResourceFormat.energy(nanojoules: value)
        }
    }

    /// Geçmiş seri grafiği için karşılık gelen ölçüt (ağ için kayıtlı seri yok).
    var resourceMetric: ResourceMetric? {
        switch self {
        case .cpu: .cpu
        case .gpu: .gpu
        case .disk: .diskWrite
        case .energy: .energy
        case .memory: .memoryPeak
        case .name, .network: nil
        }
    }
}
