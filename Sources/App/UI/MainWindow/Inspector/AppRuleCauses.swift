import SwiftUI

/// Bu uygulamayı şu an sınırlayan ya da engelleyen kurallar / kademeli limit.
struct AppRuleCauses: View {
    let model: AppModel
    let appID: String

    var body: some View {
        let causes = model.rules.causes(for: appID)
        if !causes.isEmpty {
            let statuses = model.ruleStatuses()
            InspectorSection("Aktif kurallar") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(causes, id: \.self) { cause in
                        row(for: cause, statuses: statuses)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for cause: RuleCause, statuses: [RuleStatus]) -> some View {
        switch cause {
        case .rule(let id):
            let rule = model.prefs.usageRules.first { $0.id == id }
            let status = statuses.first { $0.id == id }
            VStack(alignment: .leading, spacing: 2) {
                Label(rule.map { $0.name.isEmpty ? "Adsız kural" : $0.name } ?? "Silinmiş kural", systemImage: "list.bullet.rectangle")
                Text(detail(rule: rule, status: status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .ladder(let level):
            VStack(alignment: .leading, spacing: 2) {
                Label("Kademeli limit: \(level.title)", systemImage: "stairs")
                Text("Günlük ya da aylık kullanım eşiği aşıldığı için uygulanıyor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detail(rule: UsageRule?, status: RuleStatus?) -> String {
        var parts: [String] = []
        if let rule {
            switch rule.action {
            case .block:
                parts.append("Engel")
            case .throttle(let down, let up):
                let texts = [down.map { "↓ \(AppModel.rateText($0))" }, up.map { "↑ \(AppModel.rateText($0))" }].compactMap { $0 }
                parts.append(texts.isEmpty ? "Hız sınırı" : texts.joined(separator: " "))
            }
            parts.append(rule.scope == .mobileOnly ? "yalnızca mobil" : "tüm ağlar")
        }
        if let seconds = status?.secondsUntilReset, seconds > 0 {
            parts.append("kalkmasına \(Self.durationText(seconds))")
        }
        return parts.joined(separator: " · ")
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes) dk" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) sa" : "\(h) sa \(m) dk"
    }
}
