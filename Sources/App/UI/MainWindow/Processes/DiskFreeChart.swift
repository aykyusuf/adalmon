import SwiftUI

/// Boş alan eğilimi: GB cinsinden alan+çizgi; imleç gelince o andaki boş alan.
struct DiskFreeChart: View {
    let points: [DiskFreePoint]
    let window: ResourceWindow

    var body: some View {
        let data = points.map { ChartPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: Double($0.freeBytes) / 1e9) }
        let lo = data.map(\.value).min() ?? 0, hi = data.map(\.value).max() ?? 1
        let pad = max(0.5, (hi - lo) * 0.15)
        InteractiveLineChart(
            lines: [ChartLine(name: "Boş alan", color: .accentColor, points: data)],
            xDomain: (data.first?.date ?? .now)...max(data.last?.date ?? .now, (data.first?.date ?? .now).addingTimeInterval(60)),
            yDomain: max(0, lo - pad)...(hi + pad),
            yLabel: { $0.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR"))) + " GB" },
            timeLabel: { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) },
            xAxisValues: .automatic(desiredCount: 5),
            xLabel: { window == .days7 ? $0.formatted(.dateTime.weekday(.abbreviated).hour()) : $0.formatted(.dateTime.hour().minute()) },
            accessibilityTitle: "Boş alan grafiği")
    }
}
