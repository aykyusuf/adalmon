import Foundation

struct BatteryStatusAnswer: Equatable, Sendable {
    var level: Int
    var state: WidgetSnapshot.MacState
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    var healthPercent: Int?
}

struct DeviceBatteryAnswer: Equatable, Sendable {
    var name: String
    var level: Int?
    var isCharging: Bool
    var isConnected: Bool
}

struct MobileUsageAnswer: Equatable, Sendable {
    var todayBytes: UInt64
    var dailyCapBytes: UInt64
    var cycleUsedBytes: UInt64?
    var monthlyCapBytes: UInt64?
    var isOnMobile: Bool
}

struct IntentAppInfo: Equatable, Sendable {
    var id: String
    var name: String
}

enum AdalmonIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case noBattery
    case invalidSpeed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: "Adalmon henüz hazır değil. Uygulamayı bir kez açıp tekrar dene."
        case .noBattery: "Bu Mac'te pil yok."
        case .invalidSpeed: "Hız sınırı en az 1 KB/sn olmalı."
        }
    }
}

/// Kestirmelerin uygulamaya eriştiği tek yüz. Gerçeği `LiveIntentBackend`, testlerde sahte.
@MainActor
protocol AdalmonIntentBackend: AnyObject {
    func batteryStatus() -> BatteryStatusAnswer?
    func deviceBatteries() -> [DeviceBatteryAnswer]
    func mobileUsage() -> MobileUsageAnswer
    func open(route: AdalmonRoute)
    func setThrottle(appID: String, limit: AppLimit)
    func removeThrottle(appID: String)
    func setBlockedOnMobile(appID: String, blocked: Bool)
    func knownApps() -> [IntentAppInfo]
    func appName(for id: String) -> String
}

@MainActor
enum AdalmonIntentHub {
    static var backend: (any AdalmonIntentBackend)?

    static func require() throws -> any AdalmonIntentBackend {
        guard let backend else { throw AdalmonIntentError.notReady }
        return backend
    }
}

/// Parametre → eylem dönüşümü ve cevap metinleri (saf).
enum IntentMapping {
    /// 1 KB = 1024 bayt (uygulamadaki hız sınırı gösterimiyle aynı).
    static func limit(kilobytesPerSecond: Int, onlyOnMobile: Bool) -> AppLimit? {
        guard kilobytesPerSecond >= 1 else { return nil }
        let bytes = min(kilobytesPerSecond, 10_000_000) * 1024
        return AppLimit(downBytesPerSec: bytes, upBytesPerSec: bytes, onlyOnMobile: onlyOnMobile)
    }

    static func batteryText(_ a: BatteryStatusAnswer) -> String {
        switch a.state {
        case .full: return "Pil %\(a.level), tam şarjlı."
        case .charging:
            return "Pil %\(a.level), şarj oluyor" + (a.minutesToFull.map { "; %100'e \(WidgetFormat.duration(minutes: $0))" } ?? "") + "."
        case .pluggedNotCharging: return "Pil %\(a.level), takılı ama şarj olmuyor."
        case .onBattery:
            return "Pil %\(a.level), pilde" + (a.minutesToEmpty.map { "; \(WidgetFormat.duration(minutes: $0)) kaldı" } ?? "") + "."
        }
    }

    static func devicesText(_ list: [DeviceBatteryAnswer]) -> String {
        let usable = list.filter { $0.level != nil }
        guard !usable.isEmpty else { return "Pili okunabilen cihaz yok." }
        return usable.map { "\($0.name) %\($0.level ?? 0)" + ($0.isCharging ? " (şarjda)" : "") }.joined(separator: ", ") + "."
    }

    static func mobileText(_ a: MobileUsageAnswer) -> String {
        var t = "Bugün mobil veri: \(WidgetFormat.bytes(a.todayBytes)) / \(WidgetFormat.bytes(a.dailyCapBytes))"
        if let used = a.cycleUsedBytes, let cap = a.monthlyCapBytes { t += "; dönem: \(WidgetFormat.bytes(used)) / \(WidgetFormat.bytes(cap))" }
        return t + "."
    }
}
