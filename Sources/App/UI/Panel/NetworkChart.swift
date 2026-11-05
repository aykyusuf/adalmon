import Charts
import SwiftUI

/// Son 60 saniyelik indirme (alan) ve yükleme (çizgi) grafiği.
struct NetworkChart: View {
    let down: [Double]
    let up: [Double]

    var body: some View {
        let peak = max(down.max() ?? 0, up.max() ?? 0, 50_000)
        Chart {
            ForEach(Array(down.enumerated()), id: \.offset) { p in
                AreaMark(x: .value("t", p.offset), y: .value("↓", p.element), series: .value("s", "down"))
                    .foregroundStyle(.linearGradient(colors: [.blue.opacity(0.4), .blue.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(up.enumerated()), id: \.offset) { p in
                LineMark(x: .value("t", p.offset), y: .value("↑", p.element), series: .value("s", "up"))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...(AppModel.historyLength - 1))
        .chartYScale(domain: 0...peak * 1.1)
        .padding(4)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 9))
        .accessibilityLabel("Son 60 saniye ağ trafiği")
    }
}
