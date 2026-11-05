import Foundation

/// Menü çubuğunda gösterilebilen metrik.
enum MetricKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, gpu, memory, disk, temperature, network, mobileData, connection

    var id: String { rawValue }

    /// Ayarlarda görünen ad.
    var displayName: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Bellek"
        case .disk: "Disk"
        case .temperature: "Sıcaklık"
        case .network: "Ağ"
        case .mobileData: "Mobil veri"
        case .connection: "Bağlantı"
        }
    }

    /// Varsayılan eşikler; sıcaklıkta değer °C/100 olduğundan 70/85 °C.
    var defaultThresholds: Thresholds {
        self == .temperature ? Thresholds(warning: 0.70, critical: 0.85) : Thresholds()
    }

    /// Menü çubuğunda etiket olarak çizilen kısa ad.
    var shortLabel: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "RAM"
        case .disk: "DSK"
        case .temperature: "ISI"
        case .network: "AĞ"
        case .mobileData: "MOB"
        case .connection: "BAĞ"
        }
    }

    /// Ayarlar ve "ikon + değer" stili için SF Symbol.
    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "display"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .temperature: "thermometer.medium"
        case .network: "arrow.up.arrow.down"
        case .mobileData: "antenna.radiowaves.left.and.right"
        case .connection: "wifi"
        }
    }

    /// Bu metriğin desteklediği stiller; ilki varsayılandır.
    var supportedStyles: [WidgetStyle] {
        switch self {
        case .cpu, .gpu, .memory:
            [.stacked, .text, .verticalBar, .horizontalBar, .ring, .sparkline, .dot, .iconValue]
        case .disk:
            [.stacked, .text, .verticalBar, .horizontalBar, .ring, .dot, .iconValue]
        case .temperature:
            [.stacked, .text, .ring, .verticalBar, .iconValue, .sparkline]
        case .mobileData:
            [.horizontalBar, .text, .stacked, .verticalBar, .ring, .dot, .iconValue]
        case .network:
            [.speedTwoLine, .speedOneLine, .networkChart, .sparkline, .text, .stacked, .iconValue]
        case .connection:
            [.dot, .iconValue, .text]
        }
    }

    func supports(_ style: WidgetStyle) -> Bool { supportedStyles.contains(style) }

    /// Geçmiş (60 örnek) olan metrikler.
    var hasHistory: Bool { self == .cpu || self == .gpu || self == .memory || self == .network || self == .temperature }
}
