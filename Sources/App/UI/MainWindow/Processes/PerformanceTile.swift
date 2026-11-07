import SwiftUI

/// Sol listedeki kaynak kutucuğu: küçük grafik + ad + güncel değer.
struct PerformanceTile: View {
    let metric: PerformanceMetric
    let values: [Double]
    let headline: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PerformanceSparkline(values: values, color: metric.color)
                    .frame(width: 68, height: 46)
                    .background(metric.color.opacity(0.08), in: .rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(metric.color.opacity(0.5), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(headline).font(.caption).monospacedDigit().lineLimit(1)
                    Text(detail).font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(isSelected ? metric.color.opacity(0.16) : Color.primary.opacity(0.04), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? metric.color.opacity(0.7) : .clear, lineWidth: 1.5))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title), \(headline), \(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
