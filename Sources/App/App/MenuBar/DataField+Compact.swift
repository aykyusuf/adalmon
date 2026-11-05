import Foundation

/// Text and labels used by the compact card layouts (`ComponentVisual.isCompact`).
extension DataField {
    /// Label shared by all values of one card, written once: "CPU", "RAM".
    var groupLabel: String {
        switch self {
        case .cpu, .cpuTemp, .cpuMaxTemp: "CPU"
        case .gpu, .gpuTemp, .gpuMemory: "GPU"
        case .memoryPercent, .memoryUsed, .memoryFree, .swapUsed, .memoryPressure: "RAM"
        case .diskPercent, .diskFree, .diskRead, .diskWrite: "DSK"
        case .mobileUsed, .mobileRemaining, .mobilePercent: "MOB"
        case .ssdTemp: "SSD"
        case .batteryTemp: "PİL"
        default: label
        }
    }

    /// Fields that always carry their own label (arrows, SSD/Pil), so they can share one component.
    var needsOwnLabel: Bool {
        category == .network || self == .ssdTemp || self == .batteryTemp
    }

    /// Small label above a value column ("Etiket üstte"). Temperatures carry the unit in the label.
    func columnLabel(isFirst: Bool) -> String {
        switch self {
        case .cpuTemp, .gpuTemp: isFirst ? label : "°C"
        case .cpuMaxTemp, .ssdTemp, .batteryTemp: label
        case .memoryFree, .diskFree: isFirst ? groupLabel : "BOŞ"
        case .memoryPercent, .diskPercent, .mobilePercent: isFirst ? groupLabel : "DOLU"
        case .mobileRemaining: "KALAN"
        default: needsOwnLabel ? label : groupLabel
        }
    }

    /// SF Symbol drawn by "Simge" (per card; network uses one arrow per row instead).
    var compactSymbol: String {
        switch self {
        case .download, .downloadLast60, .downloadToday: "arrow.down"
        case .upload, .uploadLast60, .uploadToday: "arrow.up"
        case .ssdTemp, .batteryTemp, .cpuMaxTemp: "thermometer.medium"
        case .gpu, .gpuTemp, .gpuMemory: "square.stack.3d.up"
        default: category == .temperature ? "cpu" : category.symbolName
        }
    }

    /// Minimal units: "%22", "33°", "12,5GB"; `bareTemperature` drops the degree when a label already says °C.
    func compactText(_ v: WidgetValues, showUnits: Bool, unit: ByteUnit, bareTemperature: Bool = false) -> String {
        switch kind {
        case .temperature:
            guard let raw = rawValue(v) else { return "—" }
            let n = Int(raw.rounded())
            return bareTemperature ? "\(n)" : "\(n)°"
        case .bytes(let binary):
            guard let raw = rawValue(v) else { return "–" }
            let p = ByteText.parts(raw, unit: unit, binary: binary, showUnits: showUnits)
            return p.number + p.unit
        case .mobileUsage:
            return text(v, showUnits: showUnits, unit: unit).replacingOccurrences(of: " ", with: "")
        default:
            return text(v, showUnits: showUnits, unit: unit)
        }
    }

    func compactWidestTexts(_ v: WidgetValues, showUnits: Bool, unit: ByteUnit, bareTemperature: Bool = false) -> [String] {
        switch kind {
        case .temperature: [bareTemperature ? "100" : "100°"]
        case .bytes where unit == .auto:
            // Auto keeps one decimal only below 100: "1023MB", "99,9GB", "128GB" (ByteText.parts).
            [("8888", "KB"), ("8888", "MB"), ("88,8", "GB"), ("888", "GB")].map { $0 + (showUnits ? $1 : String($1.prefix(1))) }
        case .bytes: [ByteText.widest(unit: unit, showUnits: showUnits).replacingOccurrences(of: " ", with: "")]
        case .rate:
            // Format.rate: "999 KB/s", "99,9 MB/s", "999 MB/s".
            [("888", "KB/s"), ("88,8", "MB/s"), ("888", "MB/s")].map { $0 + " " + (showUnits ? $1 : String($1.prefix(1))) }
        case .mobileUsage: widestTexts(v, showUnits: showUnits, unit: unit).map { $0.replacingOccurrences(of: " ", with: "") }
        default: widestTexts(v, showUnits: showUnits, unit: unit)
        }
    }
}
