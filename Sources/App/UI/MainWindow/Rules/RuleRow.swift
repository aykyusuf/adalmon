import SwiftUI

/// Kurallar listesindeki tek kural: özet, canlı durum, aç/kapa ve menü.
struct RuleRow: View {
    @Binding var rule: UsageRule
    let status: RuleStatus?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: AppCatalog.shared.icon(for: rule.app))
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(RuleText.title(rule)).font(.headline).lineLimit(1)
                    Text("\(AppCatalog.shared.name(for: rule.app)) · \(RuleText.trigger(rule.trigger))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("\(RuleText.action(rule.action)) · \(RuleText.scope(rule.scope))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                RuleStatusLine(rule: rule, status: status)
            }
            Spacer(minLength: 8)
            Toggle("Kuralı etkinleştir", isOn: $rule.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
            Menu {
                Button("Düzenle…", systemImage: "pencil", action: onEdit)
                Button("Sil…", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Label("Daha fazla", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
        .opacity(rule.enabled ? 1 : 0.65)
        .contextMenu {
            Button("Düzenle…", systemImage: "pencil", action: onEdit)
            Button("Sil…", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .contain)
    }
}
