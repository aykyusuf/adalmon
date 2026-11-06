import SwiftUI

/// Kural listesi. Canlı durum (`ruleStatuses`) ucuz bir okumadır; her ölçümde yenilenir ve geri sayım akar.
struct RuleListSection: View {
    let model: AppModel
    @Bindable var prefs: Preferences
    let onEdit: (UsageRule) -> Void
    let onAdd: () -> Void
    @State private var deleting: UsageRule?
    @State private var isConfirmingDelete = false

    var body: some View {
        let statuses = liveStatuses()
        RulesCard(title: "Kullanım kuralları", systemImage: "shield.lefthalf.filled",
                  subtitle: "Bir uygulama eşiği aşınca hız sınırı ya da engel kendiliğinden devreye girer.") {
            if prefs.usageRules.isEmpty {
                RulesEmptyState(onAdd: onAdd)
            } else {
                ForEach($prefs.usageRules) { $rule in
                    RuleRow(rule: $rule, status: statuses[rule.id], onEdit: { onEdit(rule) }, onDelete: { confirmDelete(rule) })
                }
            }
        }
        .onChange(of: prefs.usageRules) { model.rulesDidChange() }
        .confirmationDialog(deleting.map { "“\(RuleText.title($0))” kuralı silinsin mi?" } ?? "",
                            isPresented: $isConfirmingDelete, titleVisibility: .visible, presenting: deleting) { rule in
            Button("Sil", role: .destructive) { delete(rule) }
        } message: { _ in
            Text("Kural devredeyse sınır ya da engel hemen kalkar.")
        }
    }

    /// `lastUpdate` her ölçümde değişir; okuyarak geri sayımı ve kullanım çubuklarını canlı tutarız.
    private func liveStatuses() -> [UUID: RuleStatus] {
        _ = model.lastUpdate
        return Dictionary(model.ruleStatuses(now: .now).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func confirmDelete(_ rule: UsageRule) {
        deleting = rule
        isConfirmingDelete = true
    }

    private func delete(_ rule: UsageRule) {
        prefs.usageRules.removeAll { $0.id == rule.id }
        deleting = nil
    }
}
