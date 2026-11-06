import SwiftUI

/// Kurallar sayfasındaki bölüm kartı: başlık, açıklama ve içerik.
struct RulesCard<Content: View>: View {
    let title: String
    let systemImage: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}
