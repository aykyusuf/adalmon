import SwiftUI

/// "Kartlar" görünümü: 2×2 büyük kart.
struct SystemGrid: View {
    let metrics: [SystemMetric]

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                ForEach(metrics.prefix(2)) { MetricCard(metric: $0) }
            }
            GridRow {
                ForEach(metrics.dropFirst(2).prefix(2)) { MetricCard(metric: $0) }
            }
        }
    }
}
