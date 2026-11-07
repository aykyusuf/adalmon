import SwiftUI

/// İmleç konumundaki tüm serilerin değerleri (araç ipucu + nokta işaretleri). Saf mantık.
struct ChartReadout: Equatable {
    struct Row: Identifiable, Equatable {
        var name: String
        var color: Color
        /// Serinin imlece en yakın noktası.
        var date: Date
        var value: Double
        var text: String
        var id: String { name }
    }

    var tooltipRows: [ChartTooltipRow] { rows.map { ChartTooltipRow(name: $0.name, color: $0.color, text: $0.text) } }

    /// Dikey çizginin konumu.
    var date: Date
    var title: String
    var rows: [Row]

    /// Her serinin `date`e en yakın noktası; hiç seri eşleşmezse nil.
    static func make(lines: [ChartLine], at date: Date, title: (Date) -> String, value: (Double) -> String) -> ChartReadout? {
        var rows: [Row] = []
        for line in lines {
            guard let i = ChartNearest.index(in: line.points, to: date, tolerance: ChartNearest.tolerance(for: line.points)) else { continue }
            let p = line.points[i]
            rows.append(Row(name: line.name, color: line.color, date: p.date, value: p.value, text: value(p.value)))
        }
        guard !rows.isEmpty else { return nil }
        return ChartReadout(date: date, title: title(date), rows: rows)
    }
}
