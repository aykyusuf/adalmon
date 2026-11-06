import Foundation

/// Uygulama başına kullanım kuralı: tetikleyici + eylem + ağ kapsamı.
/// `app` kimliği `AppLimit` / `blockedOnMobile` anahtarlarıyla aynıdır (`UsageBucket.app`: .app yolu ya da çalıştırılabilir yol).
struct UsageRule: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String = ""
    var enabled: Bool = true
    var app: String
    var scope: NetworkScope = .mobileOnly
    var trigger: RuleTrigger
    var action: RuleAction

    /// Kayan pencere kuralı: tetiklenince eylem en az bu kadar (pencere uzunluğu) tutulur.
    var holdSeconds: TimeInterval {
        guard !trigger.isFixedWindow else { return 0 }
        return TimeInterval(max(2, trigger.windowMinutes)) * 60
    }

    /// Gerçekten bir eylem üretebilir mi (boş hız sınırı etkisizdir).
    var hasEffect: Bool {
        switch action {
        case .block: true
        case .throttle: action.limit(scope: scope) != nil
        }
    }
}
