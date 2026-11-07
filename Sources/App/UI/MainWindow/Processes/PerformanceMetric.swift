import Foundation

/// "Performans" sekmesinin sol listesindeki kaynaklar.
enum PerformanceMetric: String, CaseIterable, Identifiable, Hashable, Sendable {
    case cpu, memory, disk, network, gpu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Bellek"
        case .disk: "Disk"
        case .network: "Ağ"
        case .gpu: "GPU"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "wifi"
        case .gpu: "display"
        }
    }
}

/// Performans grafiğinin zaman aralığı.
enum PerformanceRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case live, hour1, hours24

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Canlı"
        case .hour1: "1 sa"
        case .hours24: "24 sa"
        }
    }

    var window: ResourceWindow? {
        switch self {
        case .live: nil
        case .hour1: .hour1
        case .hours24: .hours24
        }
    }
}
