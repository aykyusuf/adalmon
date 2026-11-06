import SwiftUI

/// Sıralı çubuk listesi satırı: simge + ad + oransal çubuk + değer. İsteğe bağlı seçim.
struct ResourceRankRow: View {
    let rank: ResourceRank
    let fraction: Double
    let metric: ResourceMetric
    let coverage: Double
    var isSelected = false
    var tint: Color = .accentColor

    var body: some View {
        let text = ResourceFormat.rankText(metric: metric, value: rank.value, coverage: coverage)
        HStack(spacing: 10) {
            ResourceAppLabel(key: rank.app)
                .frame(width: 190, alignment: .leading)
            GeometryReader { geo in
                Capsule()
                    .fill(tint.opacity(0.75))
                    .frame(width: max(3, geo.size.width * fraction), height: 8)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 22)
            VStack(alignment: .trailing, spacing: 0) {
                Text(text.primary).monospacedDigit().lineLimit(1)
                if let s = text.secondary {
                    Text(s).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.14) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ResourceDisplay.name(rank.app)), \(text.primary) \(text.secondary ?? "")")
    }
}

/// Kart zemini (mevcut sayfalarla aynı).
struct ResourceCard<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let systemImage {
                Label(title, systemImage: systemImage).font(.headline).foregroundStyle(.secondary)
            } else {
                Text(title).font(.headline).foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}

/// Veri yokken / toplanırken gösterilen metin.
struct ResourceEmptyNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ResourceEmptyText {
    static let collecting = "Veri toplanıyor — ilk kayıt 1 dk içinde."
}
