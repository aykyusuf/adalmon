import SwiftUI

/// Kurallar: kullanım kuralları, kademeli limit, veri tasarrufu. Kural durumu dışında canlı veri okumaz.
struct RulesPage: View {
    let model: AppModel
    @State private var editing: RuleDraft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: MainSection.rules.title) {
                    Button("Kural ekle", systemImage: "plus", action: add)
                        .buttonStyle(.borderedProminent)
                }
                RuleListSection(model: model, prefs: model.prefs, onEdit: edit, onAdd: add)
                TierLadderSection(model: model, prefs: model.prefs)
                DataSaverSection(model: model, prefs: model.prefs)
            }
            .padding(24)
        }
        .sheet(item: $editing) { draft in
            RuleEditorSheet(model: model, draft: draft, onSave: save)
        }
    }

    private func add() {
        editing = RuleDraft()
    }

    private func edit(_ rule: UsageRule) {
        editing = RuleDraft(rule: rule)
    }

    private func save(_ rule: UsageRule) {
        let prefs = model.prefs
        if let index = prefs.usageRules.firstIndex(where: { $0.id == rule.id }) {
            prefs.usageRules[index] = rule
        } else {
            prefs.usageRules.append(rule)
        }
    }
}
