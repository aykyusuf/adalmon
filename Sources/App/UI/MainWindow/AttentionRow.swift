import SwiftUI

struct AttentionRow: View {
    let item: OverviewAttention
    let router: SettingsRouter

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .foregroundStyle(tint)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).fontWeight(.medium)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title). \(item.detail)")
        .accessibilityAddTraits(.isButton)
    }

    private var tint: Color {
        switch item.severity {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }

    private func open() {
        switch item.destination {
        case .rules: router.selectedMainSection = .rules
        case .filterSettings: router.open(.filter)
        case .app(let app):
            router.selectedAppID = app
            router.selectedMainSection = .network
        }
    }
}
