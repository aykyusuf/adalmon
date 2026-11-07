import Foundation

/// lockdownd / diagnostics_relay plist sözlüklerinden `IOSDeviceDetails` üretir (saf fonksiyon; test edilir).
/// Anahtar adları gerçek cihazda doğrulanmadı (kullanıcı bu makinede cihaz bağlamadı); her alan eksik olabilir ve
/// üst düzey, `BatteryData` ve `BatteryData.LifetimeData` içinde sırayla aranır.
enum IOSDeviceMapper {
    static func details(udid: String, connection: IOSDeviceDetails.Connection, lockdown: [String: Any], battery: [String: Any],
                        ioreg: [String: Any]?, now: Date = .now) -> IOSDeviceDetails {
        let productType = lockdown["ProductType"] as? String ?? ""
        var d = IOSDeviceDetails(udid: udid, name: (lockdown["DeviceName"] as? String) ?? "iOS cihazı", productType: productType,
                                 modelName: modelName(productType), systemVersion: lockdown["ProductVersion"] as? String,
                                 deviceSerial: lockdown["SerialNumber"] as? String, connection: connection, fetchedAt: now)
        d.level = int(battery["BatteryCurrentCapacity"])
        d.isCharging = bool(battery["BatteryIsCharging"])
        d.externalConnected = bool(battery["ExternalConnected"]) || bool(battery["ExternalChargeCapable"])
        d.fullyCharged = bool(battery["FullyCharged"])

        let root = ioregEntry(ioreg)
        let batteryData = root["BatteryData"] as? [String: Any] ?? [:]
        let lifetime = (batteryData["LifetimeData"] as? [String: Any]) ?? (root["LifetimeData"] as? [String: Any]) ?? [:]
        func find(_ keys: String...) -> Any? {
            for scope in [root, batteryData, lifetime] {
                for k in keys { if let v = scope[k] { return v } }
            }
            return nil
        }
        d.cycleCount = int(find("CycleCount"))
        d.designMAh = int(find("DesignCapacity"))
        d.nominalMAh = int(find("NominalChargeCapacity"))
        d.rawMaxMAh = int(find("AppleRawMaxCapacity"))
        d.rawCurrentMAh = int(find("AppleRawCurrentCapacity"))
        d.temperatureC = centiDegrees(find("Temperature", "VirtualTemperature"))
        d.voltageMV = int(find("Voltage", "AppleRawBatteryVoltage"))
        d.amperageMA = signed16(find("InstantAmperage", "Amperage"))
        d.batterySerial = (find("Serial", "BatterySerialNumber") as? String).flatMap { $0.isEmpty ? nil : $0 }
        d.manufacturer = (find("Manufacturer") as? String).flatMap { $0.isEmpty ? nil : $0 }
        if let cells = (find("CellVoltage") as? [Any]) { d.cellVoltagesMV = cells.compactMap(int).filter { $0 > 0 } }
        if let adapter = find("AdapterDetails") as? [String: Any] {
            d.adapterWatts = int(adapter["Watts"])
            d.adapterName = (adapter["Name"] as? String) ?? (adapter["Description"] as? String)
            d.adapterIsWireless = bool(adapter["IsWireless"])
        }
        // Ömür boyu sıcaklıklar tek ölçekte gelir (0,1 °C ya da °C); en büyük değerden ölçek seçilir.
        let tempScale = [lifetime["MaximumTemperature"], lifetime["AverageTemperature"]].compactMap(int).first.map { $0 > 100 ? 10.0 : 1.0 } ?? 1
        d.lifetimeAvgTempC = tempLifetime(lifetime["AverageTemperature"], scale: tempScale)
        d.lifetimeMinTempC = tempLifetime(lifetime["MinimumTemperature"], scale: tempScale)
        d.lifetimeMaxTempC = tempLifetime(lifetime["MaximumTemperature"], scale: tempScale)
        d.lifetimeMaxChargeMA = int(lifetime["MaximumChargeCurrent"])
        d.lifetimeMaxDischargeMA = int(lifetime["MaximumDischargeCurrent"]).map { $0 > 0 ? -$0 : $0 }
        d.lifetimeMinVoltageMV = int(lifetime["MinimumPackVoltage"])
        d.lifetimeMaxVoltageMV = int(lifetime["MaximumPackVoltage"])
        d.lifetimeOperatingHours = int(lifetime["TotalOperatingTime"])
        return d
    }

    /// `{Diagnostics: {IORegistry: {…}}}`, `{IORegistry: {…}}` ya da çıplak sözlük.
    static func ioregEntry(_ plist: [String: Any]?) -> [String: Any] {
        guard let plist else { return [:] }
        if let diag = plist["Diagnostics"] as? [String: Any] { return ioregEntry(diag) }
        if let reg = plist["IORegistry"] as? [String: Any] { return reg }
        return plist
    }

    // MARK: Değer dönüşümleri

    static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }

    static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.intValue != 0 }
        return false
    }

    /// IOKit akım değerleri bazen 64 bit işaretsiz gelir (eksi = deşarj).
    static func signed16(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber else { return nil }
        let u = n.uint64Value
        if u > UInt64(Int32.max) { return Int(Int64(bitPattern: u)) }
        return n.intValue
    }

    /// 0,01 °C birimi (ör. 2980 → 29,8). Zaten °C ise (< 100) olduğu gibi.
    static func centiDegrees(_ v: Any?) -> Double? {
        guard let n = int(v) else { return nil }
        let t = n >= 100 ? Double(n) / 100 : Double(n)
        return (-40...120).contains(t) ? t : nil
    }

    /// Ömür boyu sıcaklık: `scale` 10 ise ham değer 0,1 °C birimindedir.
    static func tempLifetime(_ v: Any?, scale: Double) -> Double? {
        guard let n = int(v) else { return nil }
        let t = Double(n) / scale
        return (-40...120).contains(t) ? t : nil
    }

    // MARK: Model adı

    static func modelName(_ productType: String) -> String {
        if let n = models[productType] { return n }
        if productType.hasPrefix("iPhone") { return "iPhone" }
        if productType.hasPrefix("iPad") { return "iPad" }
        return productType.isEmpty ? "iOS cihazı" : productType
    }

    static let models: [String: String] = [
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2. nesil)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3. nesil)", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone Air",
        "iPad13,18": "iPad (10. nesil)", "iPad14,1": "iPad mini (6. nesil)", "iPad14,3": "iPad Pro 11\" (4. nesil)", "iPad14,5": "iPad Pro 12,9\" (6. nesil)",
        "iPad13,16": "iPad Air (5. nesil)", "iPad14,8": "iPad Air 11\" (M2)", "iPad16,3": "iPad Pro 11\" (M4)", "iPad16,5": "iPad Pro 13\" (M4)",
    ]
}
