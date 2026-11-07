import Foundation

/// A single quantity that a menu bar component can show on one of its lines.
enum DataField: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, cpuTemp, cpuMaxTemp
    case gpu, gpuTemp, gpuMemory
    case memoryPercent, memoryUsed, memoryFree, swapUsed, memoryPressure
    case diskPercent, diskFree, diskRead, diskWrite, ssdTemp
    case batteryTemp, batteryLevel
    case download, upload, downloadLast60, uploadLast60, downloadToday, uploadToday
    case mobileUsed, mobileRemaining, mobilePercent
    case connection

    static let diskFullScale: Double = 500_000_000

    var id: String { rawValue }

    var category: FieldCategory {
        switch self {
        case .cpu: .cpu
        case .cpuTemp, .cpuMaxTemp: .temperature
        case .gpu, .gpuMemory: .gpu
        case .gpuTemp, .ssdTemp, .batteryTemp: .temperature
        case .batteryLevel: .battery
        case .memoryPercent, .memoryUsed, .memoryFree, .swapUsed, .memoryPressure: .memory
        case .diskPercent, .diskFree, .diskRead, .diskWrite: .disk
        case .download, .upload, .downloadLast60, .uploadLast60, .downloadToday, .uploadToday: .network
        case .mobileUsed, .mobileRemaining, .mobilePercent: .mobile
        case .connection: .connection
        }
    }

    var kind: FieldKind {
        switch self {
        case .cpu, .gpu, .memoryPercent, .diskPercent, .mobilePercent, .batteryLevel: .percent
        case .cpuTemp, .cpuMaxTemp, .gpuTemp, .ssdTemp, .batteryTemp: .temperature
        case .gpuMemory, .memoryUsed, .memoryFree, .swapUsed: .bytes(binary: true)
        case .diskFree, .downloadLast60, .uploadLast60, .downloadToday, .uploadToday, .mobileRemaining: .bytes(binary: false)
        case .diskRead, .diskWrite, .download, .upload: .rate
        case .memoryPressure: .pressure
        case .mobileUsed: .mobileUsage
        case .connection: .connection
        }
    }

    /// Free/remaining quantities: a low value is the alarming one, so their level is inverted.
    var isInverted: Bool { self == .memoryFree || self == .diskFree || self == .mobileRemaining }

    var usesByteUnit: Bool {
        if case .bytes = kind { return true }
        return false
    }

    var isTemperature: Bool { kind == .temperature }

    var displayName: String {
        switch self {
        case .cpu: "CPU kullanımı"
        case .cpuTemp: "CPU sıcaklığı"
        case .cpuMaxTemp: "CPU en sıcak çekirdek"
        case .gpu: "GPU kullanımı"
        case .gpuTemp: "GPU sıcaklığı"
        case .gpuMemory: "GPU belleği"
        case .memoryPercent: "Bellek (%)"
        case .memoryUsed: "Kullanılan bellek"
        case .memoryFree: "Boş bellek"
        case .swapUsed: "Swap"
        case .memoryPressure: "Bellek baskısı"
        case .diskPercent: "Disk doluluğu (%)"
        case .diskFree: "Boş disk"
        case .diskRead: "Disk okuma"
        case .diskWrite: "Disk yazma"
        case .ssdTemp: "SSD sıcaklığı"
        case .batteryTemp: "Pil sıcaklığı"
        case .batteryLevel: "Pil seviyesi"
        case .download: "İndirme hızı"
        case .upload: "Yükleme hızı"
        case .downloadLast60: "İndirme (son 60 sn)"
        case .uploadLast60: "Yükleme (son 60 sn)"
        case .downloadToday: "İndirme (bugün)"
        case .uploadToday: "Yükleme (bugün)"
        case .mobileUsed: "Mobil kullanım"
        case .mobileRemaining: "Mobil kalan"
        case .mobilePercent: "Mobil kota (%)"
        case .connection: "Bağlantı"
        }
    }

    var label: String {
        switch self {
        case .cpu: "CPU"
        case .cpuTemp: "CPU°"
        case .cpuMaxTemp: "CPU↑°"
        case .gpu: "GPU"
        case .gpuTemp: "GPU°"
        case .gpuMemory: "VRAM"
        case .memoryPercent, .memoryUsed: "RAM"
        case .memoryFree, .diskFree: "BOŞ"
        case .swapUsed: "SWAP"
        case .memoryPressure: "BASKI"
        case .diskPercent: "DSK"
        case .diskRead: "OKU"
        case .diskWrite: "YAZ"
        case .ssdTemp: "SSD°"
        case .batteryTemp: "PİL°"
        case .batteryLevel: "PİL"
        case .download, .downloadLast60, .downloadToday: "↓"
        case .upload, .uploadLast60, .uploadToday: "↑"
        case .mobileUsed, .mobilePercent: "MOB"
        case .mobileRemaining: "KALAN"
        case .connection: "BAĞ"
        }
    }

    var defaultThresholds: Thresholds {
        isTemperature ? Thresholds(warning: 0.70, critical: 0.85) : Thresholds()
    }

    var hasHistory: Bool {
        switch self {
        case .cpu, .gpu, .memoryPercent, .memoryUsed, .memoryFree, .download, .upload,
             .cpuTemp, .cpuMaxTemp, .gpuTemp, .ssdTemp, .batteryTemp: true
        default: false
        }
    }

    /// History normalized to 0...1 when the field has a fixed scale; rates stay raw (auto scale).
    var historyIsNormalized: Bool { kind != .rate }

    var temperatureSource: TemperatureSource? {
        switch self {
        case .cpuTemp: .cpu
        case .cpuMaxTemp: .cpuMax
        case .gpuTemp: .gpu
        case .ssdTemp: .ssd
        case .batteryTemp: .battery
        default: nil
        }
    }

    // MARK: Values

    /// Raw value: fraction for percents, °C for temperatures, bytes or bytes/s otherwise.
    func rawValue(_ v: WidgetValues) -> Double? {
        switch self {
        case .cpu: v.cpu
        case .gpu: v.gpu
        case .memoryPercent: v.memory
        case .diskPercent: v.disk
        case .mobilePercent: v.mobileCap == 0 ? 0 : Double(v.mobileUsed) / Double(v.mobileCap)
        case .batteryLevel: v.battery.map { Double($0.level) / 100 }
        case .cpuTemp, .cpuMaxTemp, .gpuTemp, .ssdTemp, .batteryTemp: temperatureSource.flatMap(v.temperature)
        case .gpuMemory: v.gpuMemory.map { Double($0) }
        case .memoryUsed: Double(v.memUsed)
        case .memoryFree: Double(v.memTotal >= v.memUsed ? v.memTotal - v.memUsed : 0)
        case .swapUsed: Double(v.swapUsed)
        case .diskFree: Double(v.diskFree)
        case .downloadLast60: Double(v.downLast60)
        case .uploadLast60: Double(v.upLast60)
        case .downloadToday: Double(v.downToday)
        case .uploadToday: Double(v.upToday)
        case .mobileRemaining: Double(v.mobileCap >= v.mobileUsed ? v.mobileCap - v.mobileUsed : 0)
        case .diskRead: v.diskRead
        case .diskWrite: v.diskWrite
        case .download: v.down
        case .upload: v.up
        case .memoryPressure: Double(v.pressure.rawValue)
        case .mobileUsed: Double(v.mobileUsed)
        case .connection: v.connection == .offline ? 0 : 1
        }
    }

    /// 0...1 level used for bars, rings and threshold colors. Free/remaining fields are inverted
    /// (1 - free/total) so that little free space reads as "high" (red).
    func level(_ v: WidgetValues) -> Double {
        let raw = rawValue(v) ?? 0
        let level: Double = switch self {
        case .cpu, .gpu, .memoryPercent, .diskPercent, .mobilePercent, .connection, .batteryLevel: raw
        case .cpuTemp, .cpuMaxTemp, .gpuTemp, .ssdTemp, .batteryTemp: raw / WidgetValues.temperatureFullScale
        case .memoryUsed, .gpuMemory: v.memTotal == 0 ? 0 : raw / Double(v.memTotal)
        case .memoryFree: v.memTotal == 0 ? 0 : 1 - raw / Double(v.memTotal)
        case .swapUsed: v.swapTotal == 0 ? 0 : raw / Double(v.swapTotal)
        case .diskFree: v.diskTotal == 0 ? 0 : 1 - raw / Double(v.diskTotal)
        case .mobileRemaining, .mobileUsed: v.mobileCap == 0 ? 0 : Double(v.mobileUsed) / Double(v.mobileCap)
        case .diskRead, .diskWrite: raw / Self.diskFullScale
        case .download, .upload: raw / WidgetValues.networkFullScale
        case .downloadLast60, .uploadLast60: raw / (WidgetValues.networkFullScale * 60)
        case .downloadToday, .uploadToday: v.mobileCap == 0 ? 0 : raw / Double(v.mobileCap)
        case .memoryPressure:
            switch v.pressure {
            case .normal: 0.2
            case .warning: 0.7
            case .critical: 1
            }
        }
        return max(0, min(1, level))
    }

    func history(_ v: WidgetValues) -> [Double] {
        switch self {
        case .cpu: v.cpuHistory
        case .gpu: v.gpuHistory
        case .memoryPercent, .memoryUsed: v.memHistory
        case .memoryFree: v.memHistory.map { 1 - $0 }
        case .download: v.downHistory
        case .upload: v.upHistory
        case .cpuTemp, .cpuMaxTemp, .gpuTemp, .ssdTemp, .batteryTemp:
            temperatureSource.map { (v.temperatureHistory[$0] ?? []).map { $0 / WidgetValues.temperatureFullScale } } ?? []
        default: []
        }
    }

    // MARK: Formatting

    func text(_ v: WidgetValues, showUnits: Bool, unit: ByteUnit = .auto) -> String {
        let raw = rawValue(v)
        switch kind {
        case .percent:
            return raw.map(Format.percent) ?? "–"
        case .temperature:
            guard let raw else { return "—" }
            let n = Int(raw.rounded())
            return showUnits ? "\(n) °C" : "\(n)°"
        case .bytes(let binary):
            guard let raw else { return "–" }
            return ByteText.text(raw, unit: unit, binary: binary, showUnits: showUnits)
        case .rate:
            let p = RateText.parts(raw ?? 0, showUnits: showUnits)
            return p.unit.isEmpty ? p.number : p.number + " " + p.unit
        case .pressure:
            return Self.pressureText(v.pressure)
        case .mobileUsage:
            let s = Self.gigabytes(v.mobileUsed) + "/" + Self.gigabytes(v.mobileCap)
            return showUnits ? s + " GB" : s
        case .connection:
            return Self.connectionText(v.connection)
        }
    }

    /// Widest possible strings for this field, used for width so the item never jitters.
    func widestTexts(_ v: WidgetValues, showUnits: Bool, unit: ByteUnit = .auto) -> [String] {
        switch kind {
        case .percent: ["%100"]
        case .temperature: [showUnits ? "100 °C" : "100°"]
        case .bytes: [ByteText.widest(unit: unit, showUnits: showUnits)]
        case .rate: [RateText.widestNumber + " " + (showUnits ? RateText.widestRateUnit : RateText.widestShortUnit)]
        case .pressure: [MemoryPressure.normal, .warning, .critical].map(Self.pressureText)
        case .mobileUsage: ["88,8/" + Self.gigabytes(v.mobileCap) + (showUnits ? " GB" : "")]
        case .connection: [ConnectionState.online, .mobile, .offline].map(Self.connectionText)
        }
    }

    static func pressureText(_ p: MemoryPressure) -> String {
        switch p {
        case .normal: "Normal"
        case .warning: "Uyarı"
        case .critical: "Kritik"
        }
    }

    static func connectionText(_ state: ConnectionState) -> String {
        switch state {
        case .online: "Wi-Fi"
        case .mobile: "Mobil"
        case .offline: "Yok"
        }
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return gb.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "tr_TR")))
    }

    func symbolName(_ v: WidgetValues) -> String {
        guard self == .connection else { return category.symbolName }
        switch v.connection {
        case .online: return "wifi"
        case .mobile: return "personalhotspot"
        case .offline: return "wifi.slash"
        }
    }
}
