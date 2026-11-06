import SwiftUI

/// Kural ekleme/düzenleme sayfası.
struct RuleEditorSheet: View {
    let model: AppModel
    @State private var draft: RuleDraft
    let onSave: (UsageRule) -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, draft: RuleDraft, onSave: @escaping (UsageRule) -> Void) {
        self.model = model
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Ad", text: $draft.name, prompt: Text("İsteğe bağlı"))
                    RuleAppField(model: model, app: $draft.app)
                }
                Section("Tetikleyici") {
                    RuleTriggerFields(draft: $draft)
                }
                Section("Eylem") {
                    RuleActionFields(draft: $draft)
                }
                Section("Ağ") {
                    Picker("Geçerli olduğu ağ", selection: $draft.scope) {
                        Text(RuleText.scope(.mobileOnly)).tag(NetworkScope.mobileOnly)
                        Text(RuleText.scope(.allNetworks)).tag(NetworkScope.allNetworks)
                    }
                    .pickerStyle(.segmented)
                    Text(draft.scope == .mobileOnly
                         ? "Sayaç da yalnızca mobil veri baytlarını sayar."
                         : "Sayaç tüm ağlardaki baytları sayar (Wi-Fi dahil).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    SummaryOrProblems(draft: draft)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("İptal", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(draft.isNew ? "Ekle" : "Kaydet", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isValid)
            }
            .padding(12)
        }
        .frame(width: 540, height: 700)
    }

    private func save() {
        guard let rule = draft.rule else { return }
        onSave(rule)
        dismiss()
    }
}
