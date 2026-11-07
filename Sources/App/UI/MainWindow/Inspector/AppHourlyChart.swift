import Charts
import SwiftUI

/// Bugünün saatlik yığılmış çubuk grafiği.
struct AppHourlyChart: View {
    let hours: [AppDetail.Hour]
    let dayStart: Date
    let emptyMessage: String

    private static let locale = Locale(identifier: "tr_TR")
    @State private var hoveredHour: Date?

    var body: some View {
        Chart {
            ForEach(hours) { hour in
                BarMark(x: .value("Saat", hour.start, unit: .hour), y: .value("Veri", hour.other))
                    .foregroundStyle(by: .value("Ağ", AppUsageSeries.other))
                BarMark(x: .value("Saat", hour.start, unit: .hour), y: .value("Veri", hour.mobile))
                    .foregroundStyle(by: .value("Ağ", AppUsageSeries.mobile))
            }
            if let hour = hours.first(where: { $0.start == hoveredHour }) {
                ChartBarSelectionMarks(x: hour.start.addingTimeInterval(1_800), title: Self.range(hour.start), rows: rows(hour))
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
        .chartPointer(as: Date.self, pointerMoved)
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

    /// İmlecin altındaki saatin başlangıcı (kayıtlı saat yoksa nil); yalnızca değişince durum yazılır.
    private func pointerMoved(_ date: Date?) {
        let start = date.flatMap { d in hours.first { $0.start <= d && d < $0.start.addingTimeInterval(3_600) }?.start }
        if hoveredHour != start { hoveredHour = start }
    }

    private func rows(_ hour: AppDetail.Hour) -> [ChartTooltipRow] {
        [ChartTooltipRow(name: AppUsageSeries.mobile, color: .orange, text: Format.bytes(hour.mobile)),
         ChartTooltipRow(name: AppUsageSeries.other, color: .blue, text: Format.bytes(hour.other)),
         ChartTooltipRow(name: "Toplam", color: .secondary, text: Format.bytes(hour.total))]
    }

    private static func range(_ start: Date) -> String {
        let end = start.addingTimeInterval(3_600)
        return "\(start.formatted(.dateTime.hour().minute().locale(locale))) – \(end.formatted(.dateTime.hour().minute().locale(locale)))"
    }
}
