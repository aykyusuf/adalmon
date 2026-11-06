import SwiftUI

/// Grafik kartı: özet toplamlar + yığılmış çubuk grafiği; boşken açıklama.
struct HistoryChartCard: View {
    let content: HistoryContent
    let isLoaded: Bool
    let range: HistoryRange
    @Binding var selectedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                LegendValue(color: MediumStyle.mobileColor, title: MediumStyle.mobileName, bytes: content.totalMobile)
                LegendValue(color: MediumStyle.wifiColor, title: MediumStyle.wifiName, bytes: content.totalOther)
                Spacer()
                Text("Toplam \(Format.bytes(content.totalMobile + content.totalOther))")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
            UsageBarChart(bars: content.bars, selectedID: $selectedID)
                .frame(height: 260)
                .overlay {
                    if isLoaded && content.isEmpty {
                        ContentUnavailableView("Bu aralıkta kayıt yok", systemImage: "chart.bar",
                                               description: Text(range == .day ? "Saatlik kayıtlar yalnızca bu özelliğin eklendiği sürümden itibaren tutulur." : "Seçili günlerde ağ kullanımı kaydedilmemiş."))
                    }
                }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}
