import SwiftUI

/// Seçili çubuğun (saat/gün) en çok kullanan uygulamaları: "14:00'te ne yedi".
struct HistoryDetailCard: View {
    let bar: HistoryBar
    let bars: [HistoryBar]
    let store: UsageStore
    @Binding var selectedID: String?
    @State private var apps: [HistoryAppBytes] = []
    @State private var isLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HistoryDetailHeader(bar: bar, hasPrevious: neighbor(-1) != nil, hasNext: neighbor(1) != nil,
                                previous: { select(-1) }, next: { select(1) })
            if apps.isEmpty {
                Text(isLoaded ? "Bu dilimde uygulama kaydı yok." : "Yükleniyor…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                let peak = Double(apps.first?.bytes ?? 1)
                ForEach(apps) { app in
                    HistoryAppRow(app: app, fraction: Double(app.bytes) / max(1, peak),
                                  loader: HistoryDetailLoader(store: store, target: bar.target))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
        .task(id: bar) { await loadApps() }
    }

    private func loadApps() async {
        // Fare çubuklar üzerinden geçerken her çubuk için sorgu atılmasın: kısa bekleme, görev iptal olunca düşer.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let loaded = await HistoryDetailLoader(store: store, target: bar.target).topApps()
        guard !Task.isCancelled else { return }
        apps = loaded
        isLoaded = true
    }

    private func neighbor(_ step: Int) -> HistoryBar? {
        guard let i = bars.firstIndex(where: { $0.id == bar.id }) else { return nil }
        let j = i + step
        return bars.indices.contains(j) ? bars[j] : nil
    }

    private func select(_ step: Int) {
        if let target = neighbor(step) { selectedID = target.id }
    }
}
