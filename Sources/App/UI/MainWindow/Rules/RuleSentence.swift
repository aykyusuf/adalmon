import Foundation

/// Düzenleyicinin altındaki özet cümle: "Safari son 10 dakikada ≥ 500 MB kullanırsa hız sınırı …".
enum RuleSentence {
    @MainActor
    static func make(_ draft: RuleDraft) -> String {
        guard let rule = draft.rule else { return "" }
        let app = draft.app.isEmpty ? "Uygulama" : AppCatalog.shared.name(for: draft.app)
        var text = "\(app): \(RuleText.trigger(rule.trigger)) → \(RuleText.action(rule.action)) (\(RuleText.scope(rule.scope).lowercased()))."
        if rule.trigger.isFixedWindow {
            text += " Pencere dolunca sayaç sıfırlanır ve eylem kalkar."
        } else {
            text += " Kullanım eşiğin %80'inin altına inince eylem kalkar."
        }
        return text
    }
}
