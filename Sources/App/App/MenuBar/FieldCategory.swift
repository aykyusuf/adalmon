import Foundation

enum FieldCategory: String, CaseIterable, Identifiable, Sendable {
    case cpu, gpu, memory, disk, temperature, battery, network, mobile, connection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Bellek"
        case .disk: "Disk"
        case .temperature: "Sıcaklık"
        case .battery: "Pil"
        case .network: "Ağ"
        case .mobile: "Mobil veri"
        case .connection: "Bağlantı"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "display"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .temperature: "thermometer.medium"
        case .battery: "battery.100percent"
        case .network: "arrow.up.arrow.down"
        case .mobile: "antenna.radiowaves.left.and.right"
        case .connection: "wifi"
        }
    }
}
