import Foundation

/// Widget'ların çizildiği anlık değerler. Çizim kapanışına güvenle taşınabilsin diye düz değer tipidir.
struct WidgetValues: Sendable, Equatable {
    /// Ağ hızının eşik/geçiş rengi için tam ölçek sayılan değeri (100 Mbit/s).
    static let networkFullScale: Double = 12_500_000
    /// Sıcaklık 0...1 değeri = °C / 100.
    static let temperatureFullScale: Double = 100

    var cpu: Double = 0
    /// GPU okunamazsa nil.
    var gpu: Double?
    var memory: Double = 0
    var disk: Double = 0
    var up: Double = 0
    var down: Double = 0
    var cpuHistory: [Double] = []
    var gpuHistory: [Double] = []
    var memHistory: [Double] = []
    var upHistory: [Double] = []
    var downHistory: [Double] = []
    var mobileUsed: UInt64 = 0
    var mobileCap: UInt64 = 3_000_000_000
    var connection: ConnectionState = .online
    var downLast60: UInt64 = 0
    var upLast60: UInt64 = 0
    var downToday: UInt64 = 0
    var upToday: UInt64 = 0
    /// Sıcaklık okunamazsa nil.
    var temperature: TemperatureStats?
    /// Sensör grubuna göre °C geçmişi (menü çubuğu katmanında tutulur).
    var temperatureHistory: [TemperatureSource: [Double]] = [:]
    var memTotal: UInt64 = 0
    var memUsed: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: MemoryPressure = .normal
    var diskTotal: UInt64 = 0
    var diskFree: UInt64 = 0
    var diskRead: Double = 0
    var diskWrite: Double = 0
    var gpuMemory: UInt64?
    var battery: BatteryGlyphState?
    /// Menü çubuğuna sabitlenmiş cihaz pilleri (cihaz kimliği → durum).
    var devices: [String: BatteryGlyphState] = [:]

    func temperature(_ source: TemperatureSource) -> Double? {
        guard let t = temperature else { return nil }
        return switch source {
        case .cpu: t.cpu
        case .cpuMax: t.cpuMax
        case .gpu: t.gpu
        case .ssd: t.ssd
        case .battery: t.battery
        }
    }

    /// Ağ widget'ının yöne göre baskın değeri (ikisi seçiliyse indirme).
    static let sample: WidgetValues = {
        func wave(_ base: Double, _ amp: Double, _ phase: Double) -> [Double] {
            (0..<60).map { i in max(0, min(1, base + amp * sin(Double(i) / 6 + phase) + amp * 0.4 * sin(Double(i) / 2.3))) }
        }
        var v = WidgetValues(cpu: 0.46, gpu: 0.28, memory: 0.78, disk: 0.62, up: 1_200_000, down: 18_400_000,
                             mobileUsed: 1_800_000_000, mobileCap: 3_000_000_000, connection: .online)
        v.cpuHistory = wave(0.4, 0.15, 0) + [0.46]
        v.gpuHistory = wave(0.25, 0.1, 1)
        v.memHistory = wave(0.76, 0.02, 2) + [0.78]
        v.downHistory = wave(0.5, 0.35, 0.5).map { $0 * 20_000_000 } + [18_400_000]
        v.upHistory = wave(0.3, 0.25, 2.5).map { $0 * 2_000_000 } + [1_200_000]
        v.downLast60 = 640_000_000
        v.upLast60 = 52_000_000
        v.downToday = 4_300_000_000
        v.upToday = 610_000_000
        v.temperature = TemperatureStats(cpu: 54, cpuMax: 71, gpu: 48, ssd: 39, battery: 31)
        v.memTotal = 17_179_869_184
        v.memUsed = UInt64(Double(v.memTotal) * 0.78)
        v.swapUsed = 1_288_490_189
        v.swapTotal = 2_147_483_648
        v.diskTotal = 994_662_584_320
        v.diskFree = 377_971_782_041
        v.diskRead = 12_400_000
        v.diskWrite = 3_400_000
        v.gpuMemory = 2_254_857_830
        v.battery = BatteryGlyphState(.sample)
        v.devices = Dictionary(uniqueKeysWithValues: DeviceBattery.samples.map { ($0.id, BatteryGlyphState(device: $0)) })
        v.temperatureHistory = [.cpu: wave(0.52, 0.06, 0).map { $0 * 100 }, .gpu: wave(0.47, 0.04, 1).map { $0 * 100 }]
        return v
    }()
}
