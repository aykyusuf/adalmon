import SwiftUI

/// Büyük grafiğin altında her serinin "ort · en az · en çok" özeti (örn. "27,1 Ort · 21,5 Min · 33,4 Maks").
struct ChartSummaryStrip: View {
    let lines: [ChartLine]
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 20) {
            ForEach(lines) { line in
                if let stats = ChartStats(values: line.points.map(\.value)) {
                    HStack(spacing: 6) {
                        Circle().fill(line.color).frame(width: 8, height: 8).accessibilityHidden(true)
                        if lines.count > 1 { Text(line.name).foregroundStyle(.secondary) }
                        Text(stats.text(format)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}
