import Foundation

/// Sıcaklık widget'ının okuduğu sensör grubu.
enum TemperatureSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, cpuMax, gpu, ssd, battery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu: "CPU ort."
        case .cpuMax: "CPU en yüksek"
        case .gpu: "GPU"
        case .ssd: "SSD"
        case .battery: "Pil"
        }
    }

    var shortLabel: String {
        switch self {
        case .cpu: "CPU°"
        case .cpuMax: "CPU↑°"
        case .gpu: "GPU°"
        case .ssd: "SSD°"
        case .battery: "PİL°"
        }
    }
}
