import SwiftUI

/// "Satırlar" görünümü: ikon, başlık, doluluk çubuğu, değer.
struct SystemMetricRow: View {
    let metric: SystemMetric

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: metric.systemImage)
                .font(.caption)
                .foregroundStyle(metric.tint)
                .frame(width: 16)
            Text(metric.title)
                .font(.caption.weight(.semibold))
                .frame(width: 34, alignment: .leading)
            UsageBar(fraction: metric.fraction, tint: metric.tint, height: 4)
            Text(metric.value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
            Text(metric.secondary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 66, alignment: .trailing)
        }
        .lineLimit(1)
        .frame(height: 18)
        .help(metric.detail.isEmpty ? metric.help : metric.detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityLabel)
        .accessibilityValue(metric.detail)
    }
}
