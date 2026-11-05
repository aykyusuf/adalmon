import SwiftUI

/// Hit area and selection outline drawn over one component in `MenuBarEditorMock`.
struct MenuBarEditorSlot: View {
    let component: MenuBarComponent
    let selected: Bool
    let dropTargeted: Bool
    let dark: Bool
    let zoom: CGFloat
    let width: CGFloat

    private var radius: CGFloat { 4 * zoom }

    private var outline: Color {
        if selected { return .accentColor }
        return dropTargeted ? Color.accentColor.opacity(0.6) : .clear
    }

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
            .overlay {
                if !component.enabled {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(dark ? Color.black.opacity(0.55) : Color.white.opacity(0.6))
                    Image(systemName: "eye.slash")
                        .font(.system(size: 8 * zoom))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(outline, lineWidth: selected ? 1.5 : 1)
            }
            .frame(width: width + 4 * zoom, height: ComponentRenderer.height * zoom + 2 * zoom)
            .contentShape(.rect)
    }
}
