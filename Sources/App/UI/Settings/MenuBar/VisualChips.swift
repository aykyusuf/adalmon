import SwiftUI

/// One chip per visual, each a live preview of the selected component drawn with that visual.
struct VisualChips: View {
    @Binding var component: MenuBarComponent
    let config: MenuBarConfig
    let values: WidgetValues

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WrapLayout(spacing: 6, lineSpacing: 6) {
            ForEach(ComponentVisual.allCases) { visual in
                chip(visual)
            }
        }
    }

    private func candidate(_ visual: ComponentVisual) -> MenuBarComponent? {
        var c = component
        c.visual = visual
        if !visual.allowsSecondLine { c.secondary = nil }
        return c.isValid ? c : nil
    }

    private func chip(_ visual: ComponentVisual) -> some View {
        let selected = component.visual == visual
        let preview = candidate(visual)
        return Button {
            guard let preview else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { component = preview }
        } label: {
            VStack(spacing: 4) {
                Group {
                    if let preview {
                        ComponentPreview(components: [preview], config: config, values: values, zoom: 1.25)
                    } else {
                        Image(systemName: "nosign")
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, height: 32)
                    }
                }
                .frame(minWidth: 64, minHeight: 34)
                Text(visual.displayName)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(5)
            .background(selected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5))
            .contentShape(.rect(cornerRadius: 9))
            .opacity(preview == nil ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(preview == nil)
        .help(preview == nil ? "\(visual.displayName) bu alanla kullanılamaz" : visual.displayName)
        .accessibilityLabel(visual.displayName)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
