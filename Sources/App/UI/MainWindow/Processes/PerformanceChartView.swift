import Charts
import SwiftUI

/// Büyük Performans grafiği: canlıda x ekseni "N sn önce", kayıtlı aralıklarda saat.
struct PerformanceChartView: View {
    let series: [PerformanceChartSeries]
    let range: PerformanceRange
    let anchor: Date
    let span: TimeInterval

    var body: some View {
        let unit = series.first?.unit ?? .percent
        let peak = series.flatMap(\.points).map(\.value).max() ?? 0
        let upper = unit == .percent ? 100.0 : Self.niceCeiling(max(1_000_000, peak * 1.15))
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { p in
                    AreaMark(x: .value("Zaman", p.date), y: .value(s.name, p.value), series: .value("Seri", s.name), stacking: .unstacked)
                        .foregroundStyle(s.color.opacity(series.count > 1 ? 0.12 : 0.22))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Zaman", p.date), y: .value(s.name, p.value), series: .value("Seri", s.name))
                        .foregroundStyle(s.color)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartYScale(domain: 0...upper)
        .chartXScale(domain: anchor.addingTimeInterval(-span)...anchor)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(unit == .percent ? "%\(Int(v))" : Format.rate(v)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Date.self) { Text(label(for: d)) }
                }
            }
        }
        .accessibilityLabel("Performans grafiği")
        .accessibilityValue(series.compactMap { s in s.points.last.map { "\(s.name) \(Int($0.value.rounded()))" } }.joined(separator: ", "))
    }

    private func label(for date: Date) -> String {
        if range == .live {
            let ago = Int(anchor.timeIntervalSince(date).rounded())
            return ago <= 0 ? "şimdi" : "\(ago) sn"
        }
        return date.formatted(range == .hours24 ? .dateTime.hour().minute() : .dateTime.hour().minute())
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
