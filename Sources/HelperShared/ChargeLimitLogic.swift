import Foundation

enum ChargeDecision: Equatable, Sendable {
    case allow
    case inhibit
}

enum ChargeDecisionReason: Equatable, Sendable {
    case batteryUnknown, belowHardFloor, unplugged, manual, disabled, topUp, belowLimit, atLimit, sailing, resumed
}

struct ChargeLimitInput: Sendable {
    var level: Int?
    var isPluggedIn: Bool
    var isFullyCharged = false
    var config: ChargeConfig
    var manualInhibit = false
    /// Şu an şarj engelli mi (SMC'den okunan ya da son bilinen). Seyir histerezisi buna dayanır.
    var currentlyInhibited: Bool
    var now: Date
}

struct ChargeLimitOutcome: Equatable, Sendable {
    var decision: ChargeDecision
    var reason: ChargeDecisionReason
    /// "Şarjı şimdi tamamla" bu turda bitti (config'ten temizlenmeli).
    var endTopUp = false
}

/// Şarj sınırı + seyir histerezisi: saf, durumsuz (durum = `currentlyInhibited`). Fail-safe: emin değilsek şarja İZİN ver.
enum ChargeLimitLogic {
    static func decide(_ i: ChargeLimitInput) -> ChargeLimitOutcome {
        let endTop = i.config.isTopUp && topUpShouldEnd(i)

        guard let level = i.level, (0...100).contains(level) else {
            return .init(decision: .allow, reason: .batteryUnknown, endTopUp: endTop)
        }
        if level < HelperConstants.hardFloorPercent {
            return .init(decision: .allow, reason: .belowHardFloor, endTopUp: endTop)
        }
        if !i.isPluggedIn {
            return .init(decision: .allow, reason: .unplugged, endTopUp: endTop)
        }
        if i.manualInhibit && !i.config.enabled {
            return .init(decision: .inhibit, reason: .manual, endTopUp: endTop)
        }
        guard i.config.enabled, i.config.isValid, i.config.limit < 100 else {
            return .init(decision: .allow, reason: .disabled, endTopUp: endTop)
        }
        if i.config.isTopUp && !endTop {
            return .init(decision: .allow, reason: .topUp)
        }
        let limit = i.config.limit
        if i.currentlyInhibited {
            // Seyir: yalnızca alt sınırın ALTINA inince şarj yeniden başlar.
            return level < i.config.sailingFloor
                ? .init(decision: .allow, reason: .resumed, endTopUp: endTop)
                : .init(decision: .inhibit, reason: .sailing, endTopUp: endTop)
        }
        return level >= limit
            ? .init(decision: .inhibit, reason: .atLimit, endTopUp: endTop)
            : .init(decision: .allow, reason: .belowLimit, endTopUp: endTop)
    }

    static func topUpShouldEnd(_ i: ChargeLimitInput) -> Bool {
        guard let started = i.config.topUpStartedAt else { return false }
        if !i.isPluggedIn || i.isFullyCharged { return true }
        if let level = i.level, level >= 100 { return true }
        let elapsed = i.now.timeIntervalSince(started)
        return elapsed > HelperConstants.topUpMaxSeconds || elapsed < -60 // saat geri alındıysa da bitir
    }
}
