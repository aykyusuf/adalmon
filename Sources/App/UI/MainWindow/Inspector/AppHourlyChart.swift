import Charts
import SwiftUI

/// Bugünün saatlik yığılmış çubuk grafiği.
struct AppHourlyChart: View {
    let hours: [AppDetail.Hour]
    let dayStart: Date
    let emptyMessage: String

    private static let locale = Locale(identifier: "tr_TR")

    var body: some View {
        Chart {
            ForEach(hours) { hour in
                BarMark(x: .value("Saat", hour.start, unit: .hour), y: .value("Veri", hour.other))
                    .foregroundStyle(by: .value("Ağ", AppUsageSeries.other))
                BarMark(x: .value("Saat", hour.start, unit: .hour), y: .value("Veri", hour.mobile))
                    .foregroundStyle(by: .value("Ağ", AppUsageSeries.mobile))
            }
        }
        .chartForegroundStyleScale(domain: AppUsageSeries.scaleDomain, range: AppUsageSeries.scaleRange)
        .chartLegend(.hidden)
        .chartXScale(domain: dayStart...dayStart.addingTimeInterval(86_400))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) {
                AxisValueLabel(format: .dateTime.hour().locale(Self.locale))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Format.bytes(UInt64(max(0, v)))) }
                }
            }
        }
        .frame(height: 110)
        .overlay {
            if hours.isEmpty {
                Text(emptyMessage)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bugünün saatlik kullanım grafiği")
        .accessibilityValue(hours.isEmpty ? "Kayıt yok" : "Toplam \(Format.bytes(hours.reduce(0) { $0 + $1.total }))")
    }
}
