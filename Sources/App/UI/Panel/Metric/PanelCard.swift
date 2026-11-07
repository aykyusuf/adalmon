import SwiftUI

/// Metrik panellerinin ortak kart zemini (cam üstüne cam konmaz: `.quaternary`).
struct PanelCard<Content: View>: View {
    var tint: Color?
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                PanelCardBackground(cornerRadius: 14)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [tint.opacity(0.12), tint.opacity(0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
            }
    }
}

/// Küçük başlık + büyük değer.
struct PanelStatTile: View {
    let title: String
    let value: String
    var caption: String?
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Başlık ........ değer" satırı.
struct PanelValueRow: View {
    let title: String
    let value: String
    var tint: Color?
    var bold = false

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).fontWeight(bold ? .semibold : .regular).foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
        }
        .font(.callout)
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Bölüm başlığı (küçük, büyük harf yok).
struct PanelGroupTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if let trailing { Text(trailing).font(.caption2).foregroundStyle(.tertiary).monospacedDigit() }
        }
        .accessibilityAddTraits(.isHeader)
    }
}
