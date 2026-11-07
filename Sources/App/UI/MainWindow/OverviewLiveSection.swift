import SwiftUI

/// Canlı sistem metrikleri (kompakt). Her saniye değişen tek bölüm burasıdır.
struct OverviewLiveSection: View {
    let data: PanelData
    /// Grafik örnekleri arasındaki yaklaşık süre (ipucu zamanı için).
    var secondsPerPoint = 2

    var body: some View {
        let metrics = SystemMetric.all(data, showTemperatures: true)
        VStack(alignment: .leading, spacing: 12) {
            Text("Canlı")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(metrics) { OverviewMetricCard(metric: $0, secondsPerPoint: secondsPerPoint) }
            }
            OverviewNetworkCard(data: data, secondsPerPoint: secondsPerPoint)
        }
    }
}
