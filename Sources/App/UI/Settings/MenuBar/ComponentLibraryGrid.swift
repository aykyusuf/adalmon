import SwiftUI

/// All ready-made components, filterable by category. Clicking a card appends it to the menu bar.
struct ComponentLibraryGrid: View {
    let config: MenuBarConfig
    let values: WidgetValues
    let onAdd: (MenuBarComponent) -> Void

    @State private var category: FieldCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WrapLayout(spacing: 6, lineSpacing: 6) {
                chip(nil, title: "Tümü", symbol: "square.grid.2x2")
                ForEach(FieldCategory.allCases) { c in
                    chip(c, title: c.displayName, symbol: c.symbolName)
                }
            }
            WrapLayout(spacing: 10, lineSpacing: 10) {
                ForEach(ComponentLibrary.entries(in: category)) { entry in
                    LibraryCard(entry: entry, config: config, values: values) { onAdd(entry.component) }
                }
            }
        }
    }

    private func chip(_ value: FieldCategory?, title: String, symbol: String) -> some View {
        let selected = category == value
        return Button {
            category = value
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.6)), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
