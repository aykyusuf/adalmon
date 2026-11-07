import Charts
import SwiftUI

/// Tek uygulamanın zaman grafiği (alan + çizgi). Kova toplamları orana çevrilir (CPU/GPU %, enerji W, yazma B/sn).
struct ResourceSeriesChart: View {
    let points: [ResourceSeriesPoint]
    let metric: ResourceMetric
    let window: ResourceWindow

    var body: some View {
        let data = points.map {
            (date: Date(timeIntervalSince1970: TimeInterval($0.ts)),
             value: ResourceFormat.seriesValue(metric: metric, bucketValue: $0.value, bucketSeconds: window.bucketSeconds))
        }
        Chart {
            ForEach(data, id: \.date) { p in
                AreaMark(x: .value("Zaman", p.date), y: .value(metric.title, p.value))
                    .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Zaman", p.date), y: .value(metric.title, p.value))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: 0...max(1e-9, (data.map(\.value).max() ?? 1) * 1.15))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(ResourceFormat.axisLabel(metric: metric, value: v)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: window == .days7 ? .dateTime.weekday(.abbreviated).hour() : .dateTime.hour().minute())
            }
        }
        .accessibilityLabel("\(metric.title) zaman grafiği")
    }
}
