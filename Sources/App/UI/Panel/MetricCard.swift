import SwiftUI

/// "Kartlar" görünümündeki büyük kart (2×2 ızgara).
struct MetricCard: View {
    let metric: SystemMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(metric.title, systemImage: metric.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(metric.secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(metric.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            Group {
                if let history = metric.history {
                    Sparkline(values: history, tint: metric.tint)
                } else {
                    UsageBar(fraction: metric.fraction, tint: metric.tint, height: 6)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: 26)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
        .help(metric.detail.isEmpty ? metric.help : metric.detail)
        .accessibilityElement(children: .combine)
    }
}
