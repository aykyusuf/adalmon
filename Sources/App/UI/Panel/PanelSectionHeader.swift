import SwiftUI

/// Daraltılabilir bölüm başlığı: chevron + başlık + sağda özet.
struct PanelSectionHeader<Accessory: View>: View {
    let title: String
    let isCollapsed: Bool
    var tint: Color = .secondary
    var isCollapsible = true
    let onToggle: () -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Button(action: onToggle) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .foregroundStyle(.tertiary)
                        .opacity(isCollapsible ? 1 : 0)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!isCollapsible)
            .accessibilityLabel(title)
            .accessibilityValue(isCollapsed ? "Daraltıldı" : "Açık")
            .accessibilityHint(isCollapsible ? (isCollapsed ? "Bölümü aç" : "Bölümü daralt") : "")
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            accessory
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}
