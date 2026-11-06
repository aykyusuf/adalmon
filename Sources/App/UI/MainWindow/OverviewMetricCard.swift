import SwiftUI

/// Tek bir sistem metriği için büyük kart: değer, ayrıntı ve eksenli geçmiş grafiği (diskte doluluk çubuğu).
struct OverviewMetricCard: View {
    let metric: SystemMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(metric.title, systemImage: metric.systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.value)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(metric.secondary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(metric.detail.isEmpty ? metric.summary : metric.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(2)
                .frame(minHeight: 28, alignment: .topLeading)
            if let history = metric.history {
                HistoryChart(values: history, tint: metric.tint)
                    .frame(height: 120)
            } else {
                UsageBar(fraction: metric.fraction, tint: metric.tint, height: 10)
                    .frame(height: 120, alignment: .center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
        .help(metric.help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.accessibilityLabel)
    }
}
