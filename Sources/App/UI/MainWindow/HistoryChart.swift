import SwiftUI

/// Geçmiş grafiği (0...1 oran): yüzde eksenli alan + çizgi. Genel bakış kartlarında kullanılır; imleç gelince değer ve
/// "yaklaşık N sn önce" görünür.
struct HistoryChart: View {
    let values: [Double]
    let tint: Color
    /// Örnekler arası yaklaşık süre (sn): ipucundaki zaman için.
    var secondsPerPoint = 2

    var body: some View {
        let count = AppModel.historyLength
        InteractiveLineChart(
            lines: [ChartLine(name: "Kullanım", color: tint, points: SampleAxis.points(values, capacity: count))],
            xDomain: SampleAxis.date(0)...SampleAxis.date(Double(max(count - 1, values.count - 1))),
            yDomain: 0...1,
            yLabel: { Format.percent($0) },
            timeLabel: { SampleAxis.ageText(of: $0, count: values.count, secondsPerPoint: secondsPerPoint) },
            yAxisPosition: .trailing,
            yAxisValues: .automatic(desiredCount: 3),
            lineWidth: 2,
            compact: true)
            .accessibilityHidden(true)
    }
}
