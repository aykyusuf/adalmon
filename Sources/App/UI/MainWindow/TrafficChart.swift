import SwiftUI

/// İndirme ve yükleme geçmişi; hız eksenli büyük sürüm. İmleç gelince ikisinin değeri ve "yaklaşık N sn önce" görünür.
struct TrafficChart: View {
    let down: [Double]
    let up: [Double]
    var secondsPerPoint = 2

    var body: some View {
        let peak = max(down.max() ?? 0, up.max() ?? 0, 50_000) * 1.1
        let count = AppModel.historyLength
        InteractiveLineChart(
            lines: [ChartLine(name: "İndirme", color: .blue, points: SampleAxis.points(down, capacity: count)),
                    ChartLine(name: "Yükleme", color: .orange, points: SampleAxis.points(up, capacity: count))],
            xDomain: SampleAxis.date(0)...SampleAxis.date(Double(max(count - 1, down.count - 1))),
            yDomain: 0...peak,
            yLabel: { Format.rate($0) },
            timeLabel: { SampleAxis.ageText(of: $0, count: down.count, secondsPerPoint: secondsPerPoint) },
            yAxisPosition: .trailing,
            yAxisValues: .automatic(desiredCount: 4),
            lineWidth: 2,
            compact: true)
            .accessibilityHidden(true)
    }
}
