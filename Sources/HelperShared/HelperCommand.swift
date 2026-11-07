import Foundation

/// Yardımcının kabul ettiği TÜM komutlar. XPC ilkelleri burada doğrulanıp bu türe çevrilir; keyfi SMC yazımı yoktur.
enum HelperCommand: Equatable, Sendable {
    case getStatus
    case setChargeLimit(enabled: Bool, limit: Int, sailingFloor: Int, topUp: Bool)
    case setChargingInhibited(Bool, ttlSeconds: Int)
    case setLowPowerMode(Bool)
    case setMagSafeLED(MagSafeLEDMode)
    /// "Tümünü kapat": sınır kapalı, şarj serbest, LED otomatik.
    case resetAll

    /// XPC'den gelen ham değerleri doğrular.
    static func chargeLimit(enabled: Bool, limit: Int, sailingFloor: Int, topUp: Bool) -> Result<HelperCommand, HelperErrorCode> {
        if let error = ChargeConfig.validate(limit: limit, sailingFloor: sailingFloor) { return .failure(error) }
        return .success(.setChargeLimit(enabled: enabled, limit: limit, sailingFloor: sailingFloor, topUp: topUp))
    }

    static func chargingInhibited(_ inhibited: Bool, ttlSeconds: Int) -> Result<HelperCommand, HelperErrorCode> {
        guard HelperConstants.manualInhibitTTL.contains(ttlSeconds) else { return .failure(.outOfRange) }
        return .success(.setChargingInhibited(inhibited, ttlSeconds: ttlSeconds))
    }

    static func magSafeLED(rawValue: Int) -> Result<HelperCommand, HelperErrorCode> {
        guard let mode = MagSafeLEDMode(rawValue: rawValue) else { return .failure(.outOfRange) }
        return .success(.setMagSafeLED(mode))
    }
}
