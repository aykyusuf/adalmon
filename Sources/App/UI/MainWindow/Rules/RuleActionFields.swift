import SwiftUI

/// Eylem: hız sınırı (↓/↑ KB/s) ya da engelle.
struct RuleActionFields: View {
    @Binding var draft: RuleDraft

    var body: some View {
        Picker("Eylem", selection: $draft.actionKind) {
            ForEach(RuleDraft.ActionKind.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        if draft.actionKind == .throttle {
            KilobyteField("İndirme ↓", kilobytes: $draft.downKB)
            KilobyteField("Yükleme ↑", kilobytes: $draft.upKB)
            Text("Boş bırakılan yön sınırsız kalır; en az biri gerekir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if draft.scope == .allNetworks {
            Label("Her ağda (Wi-Fi dahil) uygulamanın yeni bağlantıları engellenir.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Mobil veride uygulamanın interneti kesilir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
