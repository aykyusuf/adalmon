import SwiftUI

/// Seçilebilir galeri kartı: üstte canlı önizleme, altta başlık; seçiliyken vurgu çerçevesi ve onay işareti.
struct GalleryCard<Preview: View>: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { action() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                preview
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .padding(8)
            .background(.background.secondary, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white, .tint)
                        .padding(5)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isSelected && !reduceMotion ? 1.02 : 1)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
