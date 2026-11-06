import Foundation

/// Panelin "Sistem kartları" ızgarasında gösterilebilen kartlar.
enum PanelCardKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case cpu
    case gpu
    case memory
    case disk
    case temperature
    case download
    case upload

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "RAM"
        case .disk: "Disk"
        case .temperature: "Sıcaklık"
        case .download: "İndirme"
        case .upload: "Yükleme"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .temperature: "thermometer.medium"
        case .download: "arrow.down"
        case .upload: "arrow.up"
        }
    }

    /// Yeni kurulumda ızgarada görünen kartlar (3 × 2); Disk ayarlardan açılır.
    var isVisibleByDefault: Bool { self != .disk }
}
