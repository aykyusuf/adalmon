import SwiftUI

/// Tablodaki durum hücresi: engelli / hız sınırlı rozetleri ve engelle düğmesi.
struct AppStatusCell: View {
    let row: AppUsageTableRow
    let onToggleBlock: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if row.isBlocked {
                badge("Mobilde engelli", systemImage: "hand.raised.fill", color: .red)
            }
            if let text = row.limitText {
                badge(text, systemImage: "speedometer", color: .orange)
                    .help(row.limit?.onlyOnMobile == true ? "Hız sınırı yalnızca mobil veride uygulanır" : "Hız sınırı")
            }
            Spacer(minLength: 0)
            Button(row.isBlocked ? "Engeli kaldır" : "Mobilde engelle",
                   systemImage: row.isBlocked ? "hand.raised.slash" : "hand.raised",
                   action: onToggleBlock)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(row.isBlocked ? .red : .secondary)
                .help(row.isBlocked ? "Mobil veride engellendi — kaldırmak için tıkla" : "Mobil verideyken bu uygulamanın internetini kes")
        }
    }

    private func badge(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }
}
