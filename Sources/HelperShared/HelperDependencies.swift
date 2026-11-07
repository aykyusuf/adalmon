import Foundation

struct BatterySnapshot: Equatable, Sendable {
    var level: Int
    var isPluggedIn: Bool
    var isCharging: Bool
    var isFullyCharged: Bool
}

/// SMC erişimi. Gerçek uygulama yalnızca yardımcıda; testlerde sahte. `write` her zaman `SMCWriteAllowlist` ile denetlenir.
protocol SMCAccessing: Sendable {
    func descriptor(of key: SMCKey) -> SMCKeyDescriptor?
    func read(_ key: SMCKey) -> [UInt8]?
    func write(_ write: SMCWrite) -> Bool
}

protocol BatteryProviding: Sendable {
    func snapshot() -> BatterySnapshot?
}

protocol PowerSettingApplying: Sendable {
    func setLowPowerMode(_ enabled: Bool) -> Bool
    func isLowPowerModeEnabled() -> Bool
}

/// Yardımcının diske yazdığı tek durum (root'a ait dizin).
struct HelperPersistedState: Codable, Equatable, Sendable {
    var config = ChargeConfig.off
    var ledMode = MagSafeLEDMode.auto
}

protocol HelperStateStoring: Sendable {
    func load() -> HelperPersistedState?
    func save(_ state: HelperPersistedState)
}

/// 60 sn'lik zamanlayıcı yalnızca gerekirken (sınır açık ya da elle engel) çalışır.
protocol PollScheduling: Sendable {
    func setPolling(_ active: Bool)
}
