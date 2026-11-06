import SwiftUI

/// Detay paneli başlığı: büyük ikon, ad, yol ve durum rozetleri.
struct AppInspectorHeader: View {
    let appID: String
    let isBlocked: Bool
    let limit: AppLimit?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: AppCatalog.shared.icon(for: appID))
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppCatalog.shared.name(for: appID))
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text((appID as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if isBlocked || limit != nil {
                    HStack(spacing: 6) {
                        if isBlocked {
                            StatusBadge(text: "Mobilde engelli", systemImage: "hand.raised.fill", color: .red)
                        }
                        if limit != nil {
                            StatusBadge(text: "Hız sınırlı", systemImage: "speedometer", color: .orange)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
