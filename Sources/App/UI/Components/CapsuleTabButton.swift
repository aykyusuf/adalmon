import SwiftUI

/// Sekme çubuğundaki tek sekme: simge + (isteğe bağlı) etiket. Seçili kapsül `CapsuleTabBar` tarafından
/// eşleşen geometriyle (`matchedGeometryEffect`) çizilir.
struct CapsuleTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let showsLabel: Bool
    let isHovered: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                if showsLabel {
                    Text(title)
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
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
