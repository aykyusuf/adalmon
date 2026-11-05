import SwiftUI

/// A library entry: live preview, name, and a one-click add.
struct LibraryCard: View {
    let entry: LibraryEntry
    let config: MenuBarConfig
    let values: WidgetValues
    let onAdd: () -> Void

    @State private var hovering = false
    @State private var added = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 176

    /// 1.5x unless the component is too wide for the card.
    private var previewZoom: CGFloat {
        let base = MenuBarComposer.width(of: [entry.component], config: config, values: values)
        let available = Self.width - 16 - 14
        return min(1.5, available / max(base + 12, 1))
    }

    private var iconStyle: AnyShapeStyle {
        if added { return AnyShapeStyle(.green) }
        return hovering ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
    }

    private var borderStyle: AnyShapeStyle {
        hovering ? AnyShapeStyle(.tint.opacity(0.7)) : AnyShapeStyle(.separator)
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(entry.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.body)
                .foregroundStyle(iconStyle)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 7) {
            ComponentPreview(components: [entry.component], config: config, values: values, zoom: previewZoom)
                .frame(maxWidth: .infinity, minHeight: 50)
            titleRow
        }
        .padding(8)
        .frame(width: Self.width)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(borderStyle, lineWidth: hovering ? 1.5 : 0.5)
        }
        .contentShape(.rect(cornerRadius: 10))
    }

    var body: some View {
        Button {
            onAdd()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { added = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { added = false }
            }
        } label: {
            card
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Menü çubuğuna ekle: \(entry.component.title)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.title) ekle")
        .accessibilityValue(ComponentRenderer.spokenText(entry.component, values: values))
        .accessibilityAddTraits(.isButton)
    }
}
