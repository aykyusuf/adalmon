import SwiftUI

/// Sekme çubuğundaki tek sekme: simge + (isteğe bağlı) etiket. Seçili kapsül `ProcessesTabBar` tarafından
/// eşleşen geometriyle (`matchedGeometryEffect`) çizilir.
struct ProcessesTabButton: View {
    let tab: ProcessesTab
    let isSelected: Bool
    let showsLabel: Bool
    let isHovered: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                if showsLabel {
                    Text(tab.title)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, showsLabel ? 14 : 12)
            .frame(minHeight: 30)
            .background {
                if isSelected {
                    Capsule().fill(Color.accentColor.opacity(0.26))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if isHovered {
                    Capsule().fill(Color.primary.opacity(0.09))
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
