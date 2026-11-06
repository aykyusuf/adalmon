import Foundation

/// Kural düzenleyicisinin form durumu. Geçerliyse `UsageRule`'a çevrilir (saf; testlenebilir).
struct RuleDraft: Identifiable, Equatable {
    enum TriggerKind: String, CaseIterable, Identifiable {
        case rolling, fixedWindow
        var id: String { rawValue }
        var title: String { self == .rolling ? "Kayan pencere" : "Sabit pencere" }
    }

    enum Unit: String, CaseIterable, Identifiable {
        case megabytes, gigabytes
        var id: String { rawValue }
        var title: String { self == .megabytes ? "MB" : "GB" }
        var bytes: Double { self == .megabytes ? 1_000_000 : 1_000_000_000 }
    }

    enum ActionKind: String, CaseIterable, Identifiable {
        case throttle, block
        var id: String { rawValue }
        var title: String { self == .throttle ? "Hız sınırı" : "Engelle" }
    }

    /// Hız sınırı için KB/s ↔ byte/sn dönüşümü (`AppModel.rateText` ile aynı: 1 KB = 1024 B).
    static let bytesPerKB = 1024.0

    var id = UUID()
    var isNew = true
    var name = ""
    var enabled = true
    var app = ""
    var scope = NetworkScope.mobileOnly
    var triggerKind = TriggerKind.rolling
    var minutes = 10
    var hours = 3
    var amount = 500.0
    var unit = Unit.megabytes
    var actionKind = ActionKind.throttle
    var downKB: Double? = 256
    var upKB: Double?

    init() {}

    init(rule: UsageRule) {
        id = rule.id
        isNew = false
        name = rule.name
        enabled = rule.enabled
        app = rule.app
        scope = rule.scope
        switch rule.trigger {
        case .rolling(let m, let bytes):
            triggerKind = .rolling
            minutes = m
            (amount, unit) = Self.split(bytes)
        case .fixedWindow(let m, let bytes):
            triggerKind = .fixedWindow
            hours = max(1, m / 60)
            minutes = m
            (amount, unit) = Self.split(bytes)
        }
        switch rule.action {
        case .block:
            actionKind = .block
        case .throttle(let down, let up):
            actionKind = .throttle
            downKB = down.map { Double($0) / Self.bytesPerKB }
            upKB = up.map { Double($0) / Self.bytesPerKB }
        }
    }

    private static func split(_ bytes: UInt64) -> (Double, Unit) {
        bytes >= 1_000_000_000 ? (Double(bytes) / 1_000_000_000, .gigabytes) : (Double(bytes) / 1_000_000, .megabytes)
    }

    var thresholdBytes: UInt64 { UInt64(max(0, amount) * unit.bytes) }

    /// Kaydetmeyi engelleyen sorunlar (boşsa form geçerli).
    var problems: [String] {
        var out: [String] = []
        if app.isEmpty { out.append("Bir uygulama seç.") }
        if !(amount > 0) { out.append("Eşik sıfırdan büyük olmalı.") }
        switch triggerKind {
        case .rolling:
            if !(1...RuleTrigger.maxRollingMinutes).contains(minutes) { out.append("Kayan pencere 1–\(RuleTrigger.maxRollingMinutes) dakika olmalı.") }
        case .fixedWindow:
            if !(1...RuleTrigger.maxFixedMinutes / 60).contains(hours) { out.append("Sabit pencere 1–\(RuleTrigger.maxFixedMinutes / 60) saat olmalı.") }
        }
        if actionKind == .throttle, (downKB ?? 0) <= 0, (upKB ?? 0) <= 0 {
            out.append("En az bir yön için hız sınırı gir.")
        }
        return out
    }

    var isValid: Bool { problems.isEmpty }

    var trigger: RuleTrigger {
        switch triggerKind {
        case .rolling: .rolling(minutes: minutes, bytes: thresholdBytes)
        case .fixedWindow: .fixedWindow(hours: hours, bytes: thresholdBytes)
        }
    }

    var action: RuleAction {
        switch actionKind {
        case .block: .block
        case .throttle:
            .throttle(downBytesPerSec: (downKB ?? 0) > 0 ? Int((downKB ?? 0) * Self.bytesPerKB) : nil,
                      upBytesPerSec: (upKB ?? 0) > 0 ? Int((upKB ?? 0) * Self.bytesPerKB) : nil)
        }
    }

    /// Geçerliyse kayıt edilecek kural.
    var rule: UsageRule? {
        guard isValid else { return nil }
        return UsageRule(id: id, name: name.trimmingCharacters(in: .whitespaces), enabled: enabled, app: app,
                         scope: scope, trigger: trigger, action: action)
    }
}
