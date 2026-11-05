import SwiftUI

/// Tek satırdaki dört küçük karodan biri: başlık, değer, ek bilgi ve minik grafik. Dokununca ayrıntıyı açar.
struct SystemTile: View {
    let metric: SystemMetric
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Text(metric.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text(metric.tileSecondary.isEmpty ? metric.secondary : metric.tileSecondary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.75)
                }
                .lineLimit(1)
                Text(metric.value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                Group {
                    if let history = metric.history {
                        Sparkline(values: history, tint: metric.tint)
                    } else {
                        UsageBar(fraction: metric.fraction, tint: metric.tint, height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 12)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(isSelected ? 0.1 : 0.05), in: .rect(cornerRadius: 9))
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(metric.help)
        .accessibilityLabel(metric.accessibilityLabel)
        .accessibilityHint(isSelected ? "Ayrıntıyı gizle" : "Ayrıntıyı göster")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
