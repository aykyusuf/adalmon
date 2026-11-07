import SwiftUI

/// Grafik üzerinde imleç yanında görünen değer kutusu: zaman + her serinin adı ve değeri.
struct ChartTooltip: View {
    let title: String
    let rows: [ChartTooltipRow]
    /// Küçük grafiklerde tek satır: "başlık · değer".
    var compact = false

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 6) {
                    Text(title).foregroundStyle(.secondary)
                    ForEach(rows) { row in
                        Circle().fill(row.color).frame(width: 6, height: 6)
                        Text(row.text).fontWeight(.semibold).monospacedDigit()
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.secondary)
                    ForEach(rows) { row in
                        HStack(spacing: 6) {
                            Circle().fill(row.color).frame(width: 7, height: 7)
                            if rows.count > 1 { Text(row.name).foregroundStyle(.secondary) }
                            Spacer(minLength: 10)
                            Text(row.text).fontWeight(.semibold).monospacedDigit()
                        }
                    }
                }
            }
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 3 : 6)
        .fixedSize()
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
        .allowsHitTesting(false)
    }
}
