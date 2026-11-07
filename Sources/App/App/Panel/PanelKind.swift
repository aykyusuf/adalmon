import Foundation

/// Menü çubuğu panelinin içeriği: her metriğin kendi paneli ya da eski birleşik panel.
enum PanelKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, gpu, memory, disk, network, temperature, battery, combined

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Bellek"
        case .disk: "Disk"
        case .network: "Ağ"
        case .temperature: "Sıcaklık"
        case .battery: "Pil"
        case .combined: "Birleşik panel"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "display"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "arrow.up.arrow.down"
        case .temperature: "thermometer.medium"
        case .battery: "battery.100percent"
        case .combined: "square.grid.2x2"
        }
    }

    /// Süreç örnekleyicisi (ilk 5 uygulama) gerektiren paneller.
    var needsLiveProcesses: Bool { self == .cpu || self == .gpu || self == .memory }

    /// Pil ve cihaz örnekleyicileri (5 sn okuma, Bluetooth taraması) yalnızca bu panellerde çalışır.
    var needsBatterySampling: Bool { self == .battery || self == .combined }
}

/// Ayarlar › Menü çubuğu › "Tıklayınca".
enum PanelClickMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case perMetric, combined

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .perMetric: "Metriğin kendi paneli"
        case .combined: "Birleşik panel"
        }
    }
}
