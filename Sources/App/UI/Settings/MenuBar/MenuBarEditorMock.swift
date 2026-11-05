import SwiftUI

/// Clickable live menu bar: one composed image (exactly what the status item draws) with hit areas
/// laid out from `MenuBarComposer.frames`. Click selects, drag reorders, ←/→ move, ⌫ deletes.
struct MenuBarEditorMock: View {
    let config: MenuBarConfig
    let values: WidgetValues
    @Binding var selection: MenuBarComponent.ID?
    var dark = true
    var zoom: CGFloat = 2
    /// Off for static renders (ImageRenderer cannot draw drag/focus hosts).
    var interactive = true
    var onMove: (MenuBarComponent.ID, MenuBarComponent.ID) -> Void = { _, _ in }
    var onMoveBy: (MenuBarComponent.ID, Int) -> Void = { _, _ in }
    var onDelete: (MenuBarComponent.ID) -> Void = { _ in }

    @State private var dropTarget: MenuBarComponent.ID?
    @FocusState private var focused: Bool

    private var components: [MenuBarComponent] { config.components }

    var body: some View {
        let frames = MenuBarComposer.frames(of: components, config: config, values: values)
        let image = MenuBarComposer.image(for: components, config: config, values: values,
                                          appearance: dark ? .darkAqua : .aqua, zoom: zoom)
        ZStack(alignment: .topTrailing) {
            wallpaper
            HStack(spacing: 14 * zoom) {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image)
                    ForEach(Array(zip(components, frames)), id: \.0.id) { component, frame in
                        if interactive {
                            slot(component, frame: frame)
                        } else {
                            staticSlot(component, frame: frame)
                        }
                    }
                }
                .frame(width: image.size.width, height: image.size.height, alignment: .topLeading)
                if components.isEmpty {
                    Text("Kitaplıktan bileşen ekle")
                        .font(.system(size: 11 * zoom))
                        .foregroundStyle(.secondary)
                }
                systemItems
            }
            .padding(.horizontal, 10 * zoom)
            .frame(height: 24 * zoom)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(dark ? Color.black.opacity(0.3) : Color.white.opacity(0.45))
        }
        .frame(height: 24 * zoom + 14)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                                                                 lineWidth: focused ? 2 : 0.5))
        .environment(\.colorScheme, dark ? .dark : .light)
        .focusable(interactive)
        .focusEffectDisabled()
        .focused($focused)
        .onMoveCommand { direction in
            guard let id = selection else { return }
            switch direction {
            case .left: onMoveBy(id, -1)
            case .right: onMoveBy(id, 1)
            default: break
            }
        }
        .onDeleteCommand {
            if let id = selection { onDelete(id) }
        }
    }

    private func staticSlot(_ component: MenuBarComponent, frame: ClosedRange<CGFloat>) -> some View {
        MenuBarEditorSlot(component: component, selected: selection == component.id, dropTargeted: false,
                          dark: dark, zoom: zoom, width: (frame.upperBound - frame.lowerBound) * zoom)
            .offset(x: frame.lowerBound * zoom - 2 * zoom, y: -zoom)
    }

    private func slot(_ component: MenuBarComponent, frame: ClosedRange<CGFloat>) -> some View {
        MenuBarEditorSlot(component: component, selected: selection == component.id, dropTargeted: dropTarget == component.id,
                          dark: dark, zoom: zoom, width: (frame.upperBound - frame.lowerBound) * zoom)
            .offset(x: frame.lowerBound * zoom - 2 * zoom, y: -zoom)
            .onTapGesture {
                selection = component.id
                focused = true
            }
            .draggable(component.id.uuidString) {
                ComponentPreview(components: [component], config: config, values: values, zoom: 1.5)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
                onMove(id, component.id)
                selection = id
                return true
            } isTargeted: { targeted in
                if targeted {
                    dropTarget = component.id
                } else if dropTarget == component.id {
                    dropTarget = nil
                }
            }
            .help(component.title)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(component.title)
            .accessibilityValue(ComponentRenderer.spokenText(component, values: values))
            .accessibilityAddTraits(selection == component.id ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { selection = component.id }
    }

    private var systemItems: some View {
        HStack(spacing: 12 * zoom) {
            Image(systemName: "wifi")
            Image(systemName: "switch.2")
            Text("09:41")
        }
        .font(.system(size: 13 * zoom, weight: .medium))
        .foregroundStyle(dark ? .white : .black)
        .opacity(0.85)
        .accessibilityHidden(true)
    }

    private var wallpaper: some View {
        LinearGradient(colors: dark
                       ? [Color(red: 0.11, green: 0.13, blue: 0.20), Color(red: 0.20, green: 0.22, blue: 0.30)]
                       : [Color(red: 0.86, green: 0.88, blue: 0.92), Color(red: 0.93, green: 0.92, blue: 0.90)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
