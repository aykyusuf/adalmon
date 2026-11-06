import SwiftUI

/// Kompakt canlı metrik kartı: başlık + büyük değer + ince geçmiş çizgisi.
struct OverviewMetricCard: View {
    let metric: SystemMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(metric.title, systemImage: metric.systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.value)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(metric.secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(metric.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            if let history = metric.history {
                HistoryChart(values: history, tint: metric.tint)
                    .frame(height: 44)
            } else {
                UsageBar(fraction: metric.fraction, tint: metric.tint, height: 8)
                    .frame(height: 44, alignment: .center)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 14))
        .help(metric.detail.isEmpty ? metric.help : metric.detail)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.accessibilityLabel)
    }
}
