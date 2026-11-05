import SwiftUI

/// Small preset cards with a live preview; the matching preset is highlighted.
struct PresetStrip: View {
    let config: MenuBarConfig
    let values: WidgetValues
    let current: MenuBarPreset?
    var scrolls = true
    let onApply: (MenuBarPreset) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if scrolls {
            ScrollView(.horizontal) { cards }
                .scrollIndicators(.hidden)
        } else {
            WrapLayout(spacing: 8, lineSpacing: 8) {
                ForEach(MenuBarPreset.allCases) { preset in
                    card(preset)
                }
            }
        }
    }

    private var cards: some View {
        HStack(spacing: 8) {
            ForEach(MenuBarPreset.allCases) { preset in
                card(preset)
            }
        }
        .padding(.vertical, 2)
    }

    private func card(_ preset: MenuBarPreset) -> some View {
        let selected = current == preset
        var preview = config
        preview.components = preset.components
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { onApply(preset) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ComponentPreview(components: preview.enabledComponents, config: preview, values: values, zoom: 1)
                    .frame(height: 30)
                HStack(spacing: 4) {
                    Text(preset.displayName)
                        .font(.caption.weight(.medium))
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
            }
            .padding(6)
            .background(.background.secondary, in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: selected ? 2 : 0.5))
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(preset.summary)
        .accessibilityLabel("\(preset.displayName) düzeni")
        .accessibilityHint(preset.summary)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
