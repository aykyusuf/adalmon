import Charts
import SwiftUI

/// Seçili konumun dikey çizgisi + serilerin işaret noktaları + değer kutusu. Annotation grafik kenarlarına sığdırılır.
struct ChartSelectionMarks: ChartContent {
    let readout: ChartReadout
    var compact = false

    var body: some ChartContent {
        RuleMark(x: .value("Seçili", readout.date))
            .foregroundStyle(.secondary.opacity(0.55))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .annotation(position: .top, spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: compact ? .fit(to: .chart) : .disabled)) {
                ChartTooltip(title: readout.title, rows: readout.tooltipRows, compact: compact)
            }
        ForEach(readout.rows) { row in
            PointMark(x: .value("Seçili", row.date), y: .value(row.name, row.value))
                .foregroundStyle(row.color)
                .symbolSize(compact ? 28 : 56)
        }
    }
}
