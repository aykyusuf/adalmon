import Charts
import SwiftUI

/// Geçmiş grafiği (0...1 oran): yüzde eksenli alan + çizgi. Genel bakış kartlarında kullanılır.
struct HistoryChart: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { point in
            AreaMark(x: .value("Örnek", point.offset), y: .value("Kullanım", point.element))
                .foregroundStyle(.linearGradient(colors: [tint.opacity(0.4), tint.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Örnek", point.offset), y: .value("Kullanım", point.element))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: 0...max(AppModel.historyLength - 1, values.count - 1))
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Format.percent(v)) }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
