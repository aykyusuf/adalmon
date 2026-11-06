import SwiftUI

/// Canlı sistem metrikleri (kompakt). Her saniye değişen tek bölüm burasıdır.
struct OverviewLiveSection: View {
    let data: PanelData

    var body: some View {
        let metrics = SystemMetric.all(data, showTemperatures: true)
        VStack(alignment: .leading, spacing: 12) {
            Text("Canlı")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(metrics) { OverviewMetricCard(metric: $0) }
            }
            OverviewNetworkCard(data: data)
        }
    }
}
