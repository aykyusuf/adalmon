import Foundation

/// libimobiledevice ile okunan iPhone/iPad pil ayrıntıları (lockdownd + diagnostics_relay).
struct IOSDeviceDetails: Identifiable, Equatable, Sendable, Codable {
    enum Connection: String, Codable, Sendable {
        case usb, wifi
        var title: String { self == .usb ? "USB" : "Wi‑Fi" }
    }

    var udid: String
    var name: String
    var productType: String
    var modelName: String
    var systemVersion: String?
    var deviceSerial: String?
    var connection: Connection
    var fetchedAt: Date

    // Şarj durumu (com.apple.mobile.battery)
    var level: Int?
    var isCharging = false
    var externalConnected = false
    var fullyCharged = false

    // Sağlık ve döngü
    var cycleCount: Int?
    var designMAh: Int?
    /// NominalChargeCapacity: iOS Ayarlar'daki "Maksimum Kapasite" bunun tasarıma oranıdır.
    var nominalMAh: Int?
    var rawMaxMAh: Int?
    var rawCurrentMAh: Int?

    // Elektrik
    var temperatureC: Double?
    var voltageMV: Int?
    var amperageMA: Int?

    // Pil kimliği
    var batterySerial: String?
    var manufacturer: String?
    var cellVoltagesMV: [Int] = []

    // Şarj aleti
    var adapterWatts: Int?
    var adapterName: String?
    var adapterIsWireless = false

    // Ömür boyu (BatteryData.LifetimeData; anahtar adları cihazdan cihaza değişebilir, yoksa nil)
    var lifetimeAvgTempC: Double?
    var lifetimeMinTempC: Double?
    var lifetimeMaxTempC: Double?
    var lifetimeMaxChargeMA: Int?
    var lifetimeMaxDischargeMA: Int?
    var lifetimeMinVoltageMV: Int?
    var lifetimeMaxVoltageMV: Int?
    var lifetimeOperatingHours: Int?

    var id: String { udid }

    var healthPercent: Int? { BatteryReading.ratio(nominalMAh, designMAh) }
    var rawHealthPercent: Int? { BatteryReading.ratio(rawMaxMAh, designMAh) }

    /// Arayüz/önizleme örneği (gerçek seri ve UDID içermez).
    static let sample = IOSDeviceDetails(
        udid: "00000000-0000000000000000", name: "Yusuf iPhone", productType: "iPhone14,2", modelName: "iPhone 13 Pro", systemVersion: "27.0",
        deviceSerial: "F2LXXXXXXXXX", connection: .wifi, fetchedAt: .now, level: 79, isCharging: false, externalConnected: false,
        cycleCount: 208, designMAh: 3095, nominalMAh: 2890, rawMaxMAh: 3080, rawCurrentMAh: 2440, temperatureC: 29.8, voltageMV: 3_970, amperageMA: -312,
        batterySerial: "F5DXXXXXXXXXXXXXX", manufacturer: "Sunwoda", cellVoltagesMV: [3_968], adapterWatts: nil, adapterName: nil,
        lifetimeAvgTempC: 27.4, lifetimeMinTempC: 4.2, lifetimeMaxTempC: 45.9, lifetimeMaxChargeMA: 2_410, lifetimeMaxDischargeMA: -3_870,
        lifetimeMinVoltageMV: 3_120, lifetimeMaxVoltageMV: 4_390, lifetimeOperatingHours: 7_240)
}
