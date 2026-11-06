import Charts
import SwiftUI

/// Son 7 günün yığılmış (mobil + diğer) çubuk grafiği.
struct AppDailyBarChart: View {
    let days: [AppDetail.Day]

    private var isEmpty: Bool { days.allSatisfy { $0.total == 0 } }

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Gün", day.label), y: .value("Veri", day.other))
                    .foregroundStyle(by: .value("Ağ", AppUsageSeries.other))
                    .opacity(day.isToday ? 1 : 0.7)
                BarMark(x: .value("Gün", day.label), y: .value("Veri", day.mobile))
                    .foregroundStyle(by: .value("Ağ", AppUsageSeries.mobile))
                    .opacity(day.isToday ? 1 : 0.7)
            }
        }
        .chartForegroundStyleScale(domain: AppUsageSeries.scaleDomain, range: AppUsageSeries.scaleRange)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks { AxisValueLabel() }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Format.bytes(UInt64(max(0, v)))) }
                }
            }
        }
        .frame(height: 130)
        .overlay {
            if isEmpty {
                Text("Son 7 günde kayıt yok")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Son 7 günün kullanım grafiği")
        .accessibilityValue(summary)
    }

    private var summary: String {
        guard !isEmpty else { return "Kayıt yok" }
        return days.map { "\($0.label) \(Format.bytes($0.total))" }.joined(separator: ", ")
    }
}
