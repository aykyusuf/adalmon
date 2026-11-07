import Charts
import SwiftUI

/// Büyük Performans grafiği: etkileşimli (imleç gelince değerler), canlıda tamponun son 10 dakikası, kayıtlı aralıklarda saat.
struct PerformanceChartView: View {
    let series: [PerformanceChartSeries]
    let range: PerformanceRange
    let anchor: Date
    let span: TimeInterval
    var onHoverChange: ((Bool) -> Void)?

    var body: some View {
        let unit = series.first?.unit ?? .percent
        let peak = series.flatMap(\.points).map(\.value).max() ?? 0
        let upper = unit == .percent ? 100.0 : Self.niceCeiling(max(1_000_000, peak * 1.15))
        InteractiveLineChart(
            lines: series.map(\.line),
            xDomain: anchor.addingTimeInterval(-span)...anchor,
            yDomain: 0...upper,
            yLabel: { PerformanceSeriesBuilder.valueText($0, unit: unit) },
            timeLabel: timeText(_:),
            yAxisLabel: { unit == .percent ? "%\(Int($0.rounded()))" : Format.rate($0) },
            yAxisValues: .automatic(desiredCount: 4),
            xAxisValues: .automatic(desiredCount: 5),
            xLabel: { $0.formatted(.dateTime.hour().minute()) },
            accessibilityTitle: "Performans grafiği",
            accessibilitySummary: series.compactMap { s in s.points.last.map { "\(s.name) \(PerformanceSeriesBuilder.valueText($0.value, unit: unit))" } }.joined(separator: ", "),
            onHoverChange: onHoverChange)
    }

    private func timeText(_ date: Date) -> String {
        switch range {
        case .live: date.formatted(.dateTime.hour().minute().second())
        case .hour1: date.formatted(.dateTime.hour().minute())
        case .hours24: date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
    }

    /// 1, 2, 5 × 10^n tavanı (eksen yuvarlak sayılarda bitsin).
    static func niceCeiling(_ v: Double) -> Double {
        guard v > 0 else { return 1 }
        let exp = pow(10, floor(log10(v)))
        let m = v / exp
        let nice: Double = m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10
        return nice * exp
    }
}
