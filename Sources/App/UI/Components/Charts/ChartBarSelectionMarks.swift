import Charts
import SwiftUI

/// Çubuk grafiklerde (kategori ya da saat x ekseni) seçili çubuğun ince dikey çizgisi + değer kutusu.
struct ChartBarSelectionMarks<X: Plottable>: ChartContent {
    let x: X
    let title: String
    let rows: [ChartTooltipRow]

    var body: some ChartContent {
        RuleMark(x: .value("Seçili", x))
            .foregroundStyle(.secondary.opacity(0.35))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                ChartTooltip(title: title, rows: rows)
            }
    }
}
