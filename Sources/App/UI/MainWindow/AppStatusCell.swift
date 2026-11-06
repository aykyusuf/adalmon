import SwiftUI

/// Tablodaki durum hücresi: engelli / hız sınırlı rozetleri ve engelle düğmesi.
struct AppStatusCell: View {
    let row: AppUsageTableRow
    let onToggleBlock: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if row.isBlocked {
                StatusBadge(text: "Mobilde engelli", systemImage: "hand.raised.fill", color: .red)
            }
            if let text = row.limitText {
                StatusBadge(text: text, systemImage: "speedometer", color: .orange)
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
}
