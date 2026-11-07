import Foundation

/// Yardımcının durum özeti (JSON olarak XPC'den döner).
struct HelperStatus: Codable, Equatable, Sendable {
    var protocolVersion = HelperConstants.protocolVersion
    /// Bu Mac'te doğrulanmış bir şarj engelleme anahtarı var mı ("CHTE" ya da "CH0B+CH0C").
    var inhibitMethod: ChargeInhibitMethod?
    var supportsMagSafeLED = false
    var config = ChargeConfig.off
    /// SMC'den okunan gerçek durum (nil = okunamadı / destek yok).
    var isInhibitingCharge: Bool?
    var manualInhibitUntil: Date?
    var ledMode = MagSafeLEDMode.auto
    var batteryLevel: Int?
    var isPluggedIn: Bool?
    var lowPowerMode = false
    var lastError: HelperErrorCode?
    var lastEvaluation: Date?

    var supportsChargeLimit: Bool { inhibitMethod != nil }
}

/// Her XPC yanıtı.
struct HelperReply: Codable, Equatable, Sendable {
    var ok: Bool
    var error: HelperErrorCode?
    var status: HelperStatus

    static func success(_ status: HelperStatus) -> HelperReply { HelperReply(ok: true, error: nil, status: status) }
    static func failure(_ error: HelperErrorCode, _ status: HelperStatus) -> HelperReply { HelperReply(ok: false, error: error, status: status) }
}
