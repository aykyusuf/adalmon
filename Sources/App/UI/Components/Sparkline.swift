import Charts
import SwiftUI

/// Son 60 saniyelik küçük alan grafiği.
struct Sparkline: View {
    let values: [Double]
    let tint: Color
    /// nil ise otomatik ölçek.
    var maxValue: Double? = 1

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { point in
            AreaMark(x: .value("t", point.offset), y: .value("v", point.element))
                .foregroundStyle(.linearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", point.offset), y: .value("v", point.element))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(AppModel.historyLength - 1, values.count - 1))
        .chartYScale(domain: 0...(maxValue ?? max(values.max() ?? 1, 1)))
        .accessibilityHidden(true)
    }
}
