import Foundation

enum BatteryCable: String, Sendable, Equatable, Codable {
    case magSafe, usbC, wireless, unknown

    var title: String {
        switch self {
        case .magSafe: "MagSafe"
        case .usbC: "USB‑C"
        case .wireless: "Kablosuz"
        case .unknown: "Kablo"
        }
    }
}

/// Mac pilinin tek bir andaki durumu. Tüm alanlar saf veri; okuma `BatteryReader`, çözümleme `AppleSmartBatteryParser`.
struct BatteryReading: Sendable, Equatable {
    var timestamp = Date(timeIntervalSince1970: 0)
    /// 0...100 (IOPS yüzdesi).
    var level = 0
    var isCharging = false
    var isPluggedIn = false
    var isFullyCharged = false
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
    var cycles: Int?
    var designCycles: Int?
    var rawMaxMAh: Int?
    var rawCurrentMAh: Int?
    var designMAh: Int?
    var nominalMAh: Int?
    var voltageMV: Int?
    /// Eksi = deşarj.
    var amperageMA: Int?
    var systemPowerMW: Int?
    var batteryPowerMW: Int?
    var adapterWatts: Int?
    var adapterName: String?
    var adapterDescription: String?
    var adapterIsWireless = false
    var cable: BatteryCable = .unknown
    var temperatureC: Double?
    var lowPowerMode = false
    /// Apple'ın Ayarlar'da gösterdiği "Maksimum kapasite" (system_profiler); yoksa nil.
    var appleMaxCapacityPercent: Int?
    // Güç akışı (PowerTelemetryData + AdapterDetails). Hepsi isteğe bağlı; yoksa model V × A ile tamamlar.
    /// SystemLoad: Mac'in kendi tükettiği güç (pil şarjı hariç).
    var systemLoadMW: Int?
    /// AdapterEfficiencyLoss: adaptörde ısıya giden güç.
    var adapterEfficiencyLossMW: Int?
    var systemVoltageInMV: Int?
    var systemCurrentInMA: Int?
    /// AdapterDetails.AdapterVoltage / Current: adaptörün pazarlanan (PD) sözleşmesi.
    var adapterVoltageMV: Int?
    var adapterCurrentMA: Int?
    /// Fişin takılı olduğu port ("MagSafe 3", "USB‑C 2"); okunamazsa nil.
    var adapterPortName: String?
    /// Güç alan/veren dış aksesuarlar (USB‑C / Thunderbolt portları). Güç ölçümü yok; bkz. `PowerPortAccessory`.
    var accessories: [PowerPortAccessory] = []

    // MARK: Sağlık

    /// Juicy tarzı: AppleRawMaxCapacity / DesignCapacity.
    var rawHealthPercent: Int? { Self.ratio(rawMaxMAh, designMAh) }
    /// NominalChargeCapacity / DesignCapacity.
    var nominalHealthPercent: Int? { Self.ratio(nominalMAh, designMAh) }
    /// Öncelik: Apple'ın sayısı, yoksa nominal, yoksa ham.
    var primaryHealthPercent: Int? { appleMaxCapacityPercent ?? nominalHealthPercent ?? rawHealthPercent }

    var cycleLimit: Int { designCycles ?? 1000 }

    static func ratio(_ a: Int?, _ b: Int?) -> Int? {
        guard let a, let b, b > 0, a > 0 else { return nil }
        return Int((Double(a) / Double(b) * 100).rounded())
    }

    // MARK: Güç

    var systemPowerW: Double? { systemPowerMW.map { Double($0) / 1000 } }
    /// Mac'in kendi tükettiği güç: SystemLoad (pil şarjı hariç), yoksa SystemPowerIn.
    var macLoadW: Double? { systemLoadMW.map { Double($0) / 1000 } ?? systemPowerW }
    var batteryPowerW: Double? { batteryPowerMW.map { Double($0) / 1000 } }

    /// Etiketteki watt ("70W USB-C Power Adapter" → 70), yoksa AdapterDetails.Watts.
    var adapterLabelWatts: Int? {
        if let name = adapterName, let m = name.firstMatch(of: /(\d{2,3})\s*W/) { return Int(m.1) }
        return adapterWatts
    }

    var adapterDisplayName: String? {
        guard let name = adapterName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return name
    }

    /// Bataryaya giren (+) / bataryadan çıkan (−) güç.
    var chargeRateW: Double? {
        if let b = batteryPowerW { return b }
        guard let v = voltageMV, let a = amperageMA else { return nil }
        return Double(v) * Double(a) / 1_000_000
    }

    enum State: Equatable, Sendable { case charging, onBattery, full, pluggedNotCharging }

    var state: State {
        if isFullyCharged || (isPluggedIn && !isCharging && level >= 100) { return .full }
        if isCharging { return .charging }
        if isPluggedIn { return .pluggedNotCharging }
        return .onBattery
    }

    var isCriticalLow: Bool { !isPluggedIn && level <= 10 }

    static let sample = BatteryReading(
        timestamp: Date(), level: 78, isCharging: false, isPluggedIn: false, isFullyCharged: false,
        timeToEmptyMinutes: 192, timeToFullMinutes: nil, cycles: 178, designCycles: 1000,
        rawMaxMAh: 5132, rawCurrentMAh: 4003, designMAh: 6249, nominalMAh: 5284, voltageMV: 12_410, amperageMA: -1280,
        systemPowerMW: 15_800, batteryPowerMW: -15_800, adapterWatts: nil, adapterName: nil, adapterDescription: nil,
        adapterIsWireless: false, cable: .unknown, temperatureC: 31.4, lowPowerMode: false, appleMaxCapacityPercent: 86)

    static let sampleCharging: BatteryReading = {
        var r = sample
        r.level = 64
        r.isCharging = true
        r.isPluggedIn = true
        r.timeToFullMinutes = 40
        r.timeToEmptyMinutes = nil
        r.amperageMA = 2_950
        r.voltageMV = 12_930
        r.rawCurrentMAh = 3280
        r.systemPowerMW = 52_300
        r.batteryPowerMW = 38_400
        r.adapterWatts = 68
        r.adapterName = "70W USB-C Power Adapter "
        r.adapterDescription = "pd charger"
        r.cable = .magSafe
        r.temperatureC = 33.2
        return r
    }()
}
