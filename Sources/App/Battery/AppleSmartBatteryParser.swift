import Foundation

/// AppleSmartBattery (IORegistry) + IOPS tanımlayıcı sözlüklerini `BatteryReading`'e çevirir. Saf; testlerde plist ile beslenir.
enum AppleSmartBatteryParser {
    /// 65535 = "bilinmiyor" (TimeRemaining / AvgTimeTo*).
    static let sentinel = 65_535

    static func parse(registry: [String: Any], powerSource: [String: Any] = [:], now: Date = .now,
                      lowPowerMode: Bool = false, cable: BatteryCable? = nil) -> BatteryReading {
        // macOS 27: kapasite anahtarları BatteryData içinde; eski sürümlerde üst düzeyde.
        let data = registry["BatteryData"] as? [String: Any] ?? [:]
        func capacity(_ key: String) -> Int? { int(data[key]) ?? int(registry[key]) }

        var r = BatteryReading()
        r.timestamp = now
        r.lowPowerMode = lowPowerMode

        let level = int(powerSource[kCurrent]) ?? int(registry["CurrentCapacity"]) ?? 0
        let maxPct = int(powerSource[kMax]) ?? int(registry["MaxCapacity"]) ?? 100
        r.level = min(100, max(0, maxPct > 0 && maxPct != 100 ? level * 100 / maxPct : level))

        let plugged = bool(registry["ExternalConnected"])
            ?? ((powerSource["Power Source State"] as? String) == "AC Power")
        r.isPluggedIn = plugged ?? false
        r.isCharging = bool(registry["IsCharging"]) ?? bool(powerSource["Is Charging"]) ?? false
        r.isFullyCharged = bool(registry["FullyCharged"]) ?? bool(powerSource["Is Charged"]) ?? false

        r.timeToEmptyMinutes = minutes(powerSource["Time to Empty"]) ?? minutes(registry["AvgTimeToEmpty"])
        r.timeToFullMinutes = minutes(powerSource["Time to Full Charge"]) ?? minutes(registry["AvgTimeToFull"])
        if r.isCharging { r.timeToEmptyMinutes = nil } else { r.timeToFullMinutes = nil }
        if r.isPluggedIn && !r.isCharging { r.timeToEmptyMinutes = nil }

        r.cycles = int(registry["CycleCount"])
        r.designCycles = int(registry["DesignCycleCount9C"]) ?? int(registry["DesignCycleCount70"])
        r.rawMaxMAh = capacity("AppleRawMaxCapacity")
        r.rawCurrentMAh = capacity("AppleRawCurrentCapacity")
        r.designMAh = capacity("DesignCapacity")
        r.nominalMAh = capacity("NominalChargeCapacity")
        r.voltageMV = int(registry["Voltage"])
        r.amperageMA = signed(registry["InstantAmperage"] ?? registry["Amperage"])

        if let t = registry["PowerTelemetryData"] as? [String: Any] {
            r.systemPowerMW = int(t["SystemPowerIn"])
            r.batteryPowerMW = int(t["BatteryPower"])
        }
        if let a = registry["AdapterDetails"] as? [String: Any] {
            r.adapterWatts = int(a["Watts"])
            r.adapterName = a["Name"] as? String
            r.adapterDescription = a["Description"] as? String
            r.adapterIsWireless = bool(a["IsWireless"]) ?? false
        }
        r.cable = cable ?? inferCable(r)
        return r
    }

    private static let kCurrent = "Current Capacity"
    private static let kMax = "Max Capacity"

    static func inferCable(_ r: BatteryReading) -> BatteryCable {
        guard r.isPluggedIn else { return .unknown }
        if r.adapterIsWireless { return .wireless }
        if (r.adapterDescription ?? "").lowercased().contains("pd") || r.adapterName?.contains("USB") == true { return .usbC }
        return .unknown
    }

    // MARK: Yardımcılar

    static func int(_ any: Any?) -> Int? {
        guard let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.intValue
    }

    static func bool(_ any: Any?) -> Bool? {
        guard let n = any as? NSNumber else { return nil }
        return n.boolValue
    }

    /// Dakika; negatif ya da 65535 (bilinmiyor) → nil.
    static func minutes(_ any: Any?) -> Int? {
        guard let v = int(any), v >= 0, v != sentinel else { return nil }
        return v
    }

    /// 64-bit işaretsiz gelen akım: eksi = deşarj.
    static func signed(_ any: Any?) -> Int? {
        guard let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let raw = n.int64Value
        return abs(raw) > 100_000 ? Int(Int16(truncatingIfNeeded: raw)) : Int(raw)
    }
}
