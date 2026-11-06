import Foundation

/// Kural, eşik ve süre metinleri (saf; testlenebilir).
enum RuleText {
    /// "45 sn", "12 dk", "1 sa 5 dk", "2 gün 3 sa".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let days = total / 86_400
        let hours = total % 86_400 / 3_600
        let minutes = total % 3_600 / 60
        if days > 0 { return hours > 0 ? "\(days) gün \(hours) sa" : "\(days) gün" }
        if hours > 0 { return minutes > 0 ? "\(hours) sa \(minutes) dk" : "\(hours) sa" }
        if minutes > 0 { return "\(minutes) dk" }
        return "\(total) sn"
    }

    /// "10 dakikalık", "3 saatlik", "2 günlük".
    static func windowAdjective(minutes: Int) -> String {
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) günlük" }
        if minutes % 60 == 0 { return "\(minutes / 60) saatlik" }
        return "\(minutes) dakikalık"
    }

    /// "Son 10 dakikada ≥ 500 MB" / "3 saatlik sabit pencerede ≥ 4 GB".
    static func trigger(_ trigger: RuleTrigger) -> String {
        switch trigger {
        case .rolling(_, _): "Son \(trigger.windowMinutes) dakikada ≥ \(Format.bytes(trigger.thresholdBytes))"
        case .fixedWindow(_, _): "\(windowAdjective(minutes: trigger.windowMinutes)) sabit pencerede ≥ \(Format.bytes(trigger.thresholdBytes))"
        }
    }

    /// "Hız sınırı ↓ 256 KB/s ↑ 50 KB/s" / "Engelle".
    static func action(_ action: RuleAction) -> String {
        switch action {
        case .block: return "Engelle"
        case .throttle(let down, let up):
            let parts = [down.map { "↓ \(AppModel.rateText($0))" }, up.map { "↑ \(AppModel.rateText($0))" }].compactMap { $0 }
            return parts.isEmpty ? "Hız sınırı (sınır yok)" : "Hız sınırı " + parts.joined(separator: " ")
        }
    }

    static func scope(_ scope: NetworkScope) -> String {
        switch scope {
        case .mobileOnly: "Sadece mobil"
        case .allNetworks: "Tüm ağlar"
        }
    }

    /// Kuralın kısa başlığı: adı varsa o, yoksa uygulama adı.
    @MainActor
    static func title(_ rule: UsageRule) -> String {
        rule.name.isEmpty ? AppCatalog.shared.name(for: rule.app) : rule.name
    }
}
