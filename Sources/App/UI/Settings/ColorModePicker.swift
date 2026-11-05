import SwiftUI

/// Color chips for a component's color mode.
struct ColorModePicker: View {
    @Binding var component: MenuBarComponent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ColorMode.allCases) { mode in
                let selected = component.colorMode == mode
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { component.colorMode = mode }
                } label: {
                    HStack(spacing: 5) {
                        ColorModeSwatch(mode: mode, component: component)
                        Text(mode.displayName)
                            .font(.caption)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.leading, 4)
                    .padding(.trailing, 8)
                    .background(selected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                in: .capsule)
                    .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5))
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.displayName)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
