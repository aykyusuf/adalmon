import Foundation

/// One simple settings card; the order of cards is the order in the menu bar.
enum MetricCardKind: String, CaseIterable, Identifiable, Sendable {
    case connection, cpu, gpu, memory, disk, network, mobile, temperature

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .connection: "Bağlantı"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Bellek"
        case .disk: "Disk"
        case .network: "Ağ"
        case .mobile: "Mobil veri"
        case .temperature: "Sıcaklık (SSD/Pil)"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .connection: "wifi"
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "arrow.up.arrow.down"
        case .mobile: "antenna.radiowaves.left.and.right"
        case .temperature: "thermometer.medium"
        }
    }

    /// Value checkboxes in display order. Network uses the instant fields as canonical values.
    var options: [DataField] {
        switch self {
        case .connection: []
        case .cpu: [.cpu, .cpuTemp]
        case .gpu: [.gpu, .gpuTemp]
        case .memory: [.memoryUsed, .memoryFree, .memoryPercent]
        case .disk: [.diskFree, .diskPercent]
        case .network: [.download, .upload]
        case .mobile: [.mobileUsed, .mobileRemaining]
        case .temperature: [.ssdTemp, .batteryTemp]
        }
    }

    /// Order of values in the menu bar (network keeps upload on top, as the two-line speed always did).
    var renderOrder: [DataField] {
        self == .network ? [.upload, .download] : options
    }

    func optionTitle(_ field: DataField) -> String {
        switch field {
        case .cpu, .gpu, .memoryPercent, .diskPercent: "Yüzde"
        case .cpuTemp, .gpuTemp: "Sıcaklık"
        case .memoryUsed: "Kullanılan"
        case .memoryFree, .diskFree: "Boş"
        case .download: "↓ İndirme"
        case .upload: "↑ Yükleme"
        case .mobileUsed: "Kullanılan/limit"
        case .mobileRemaining: "Kalan"
        case .ssdTemp: "SSD"
        case .batteryTemp: "Pil"
        default: field.displayName
        }
    }

    /// Field drawn by the optional line chart ("Grafik").
    var graphField: DataField? { self == .cpu ? .cpu : nil }

    var hasLayout: Bool { self != .connection }

    init?(field: DataField) {
        switch field {
        case .connection: self = .connection
        case .cpu, .cpuTemp: self = .cpu
        case .gpu, .gpuTemp: self = .gpu
        case .memoryUsed, .memoryFree, .memoryPercent: self = .memory
        case .diskFree, .diskPercent: self = .disk
        case .download, .upload, .downloadLast60, .uploadLast60, .downloadToday, .uploadToday: self = .network
        case .mobileUsed, .mobileRemaining: self = .mobile
        case .ssdTemp, .batteryTemp: self = .temperature
        default: return nil
        }
    }
}
