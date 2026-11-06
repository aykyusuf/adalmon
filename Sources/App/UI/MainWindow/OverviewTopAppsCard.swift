import SwiftUI

/// Bugünün en çok veri kullanan 5 uygulaması. Satıra tıklamak "Ağ kullanımı"nı o uygulama seçili açar.
struct OverviewTopAppsCard: View {
    let rows: [TopAppRow]
    let showsFilterCallout: Bool
    let router: SettingsRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("En çok kullananlar", systemImage: "list.number")
                .font(.headline)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text(showsFilterCallout ? "Uygulama bazlı ölçüm için ağ filtresi gerekir." : "Bugün henüz kayıt yok.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                let peak = Double(rows.first?.bytes ?? 1)
                ForEach(rows) { row in
                    TopAppButton(row: row, fraction: Double(row.bytes) / max(1, peak), router: router)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}
