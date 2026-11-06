import Charts
import SwiftUI

/// İndirme (alan) ve yükleme (çizgi) geçmişi; hız eksenli büyük sürüm.
struct TrafficChart: View {
    let down: [Double]
    let up: [Double]

    var body: some View {
        let peak = max(down.max() ?? 0, up.max() ?? 0, 50_000) * 1.1
        Chart {
            ForEach(Array(down.enumerated()), id: \.offset) { p in
                AreaMark(x: .value("Örnek", p.offset), y: .value("İndirme", p.element), series: .value("Seri", "İndirme"))
                    .foregroundStyle(.linearGradient(colors: [.blue.opacity(0.4), .blue.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Örnek", p.offset), y: .value("İndirme", p.element), series: .value("Seri", "İndirme"))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(up.enumerated()), id: \.offset) { p in
                LineMark(x: .value("Örnek", p.offset), y: .value("Yükleme", p.element), series: .value("Seri", "Yükleme"))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: 0...max(AppModel.historyLength - 1, down.count - 1))
        .chartYScale(domain: 0...peak)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Format.rate(v)) }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
