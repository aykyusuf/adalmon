import SwiftUI

/// Yalnızca dikkat gerektiren bir durum varken görünen kart.
struct OverviewAttentionCard: View {
    let items: [OverviewAttention]
    let router: SettingsRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Dikkat", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(items) { item in
                AttentionRow(item: item, router: router)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.orange.opacity(0.35)) }
        .accessibilityElement(children: .contain)
    }
}
