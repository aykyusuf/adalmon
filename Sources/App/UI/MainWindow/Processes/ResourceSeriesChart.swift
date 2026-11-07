import SwiftUI

/// Tek uygulamanın zaman grafiği (alan + çizgi, imleç gelince değer). Kova toplamları orana çevrilir (CPU/GPU %, enerji W, yazma B/sn).
struct ResourceSeriesChart: View {
    let points: [ResourceSeriesPoint]
    let metric: ResourceMetric
    let window: ResourceWindow

    var body: some View {
        let data = points.map {
            ChartPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)),
                       value: ResourceFormat.seriesValue(metric: metric, bucketValue: $0.value, bucketSeconds: window.bucketSeconds))
        }
        let peak = max(1e-9, (data.map(\.value).max() ?? 1) * 1.15)
        let lines = [ChartLine(name: metric.title, color: .accentColor, points: data)]
        InteractiveLineChart(
            lines: lines,
            xDomain: (data.first?.date ?? .now)...max(data.last?.date ?? .now, (data.first?.date ?? .now).addingTimeInterval(60)),
            yDomain: 0...peak,
            yLabel: { ResourceFormat.axisLabel(metric: metric, value: $0) },
            timeLabel: timeText(_:),
            xAxisValues: .automatic(desiredCount: 5),
            xLabel: timeAxisText(_:),
            accessibilityTitle: "\(metric.title) zaman grafiği")
    }

    private func timeAxisText(_ date: Date) -> String {
        window == .days7 ? date.formatted(.dateTime.weekday(.abbreviated).hour()) : date.formatted(.dateTime.hour().minute())
    }

    private func timeText(_ date: Date) -> String {
        window == .hour1 ? date.formatted(.dateTime.hour().minute()) : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
