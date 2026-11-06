import Charts
import SwiftUI

/// Bugünün kümülatif mobil kullanımı; bütçe (ve farklıysa günlük limit) çizgisiyle.
struct MobileCumulativeChart: View {
    let points: [CumulativePoint]
    let loaded: Bool
    let budgetBytes: UInt64
    let dailyCapBytes: UInt64

    private static let locale = Locale(identifier: "tr_TR")

    private var dayStart: Date {
        points.first?.date ?? UsageStore.keyCalendar.startOfDay(for: .now)
    }

    private var peak: Double {
        max(Double(points.map(\.bytes).max() ?? 0), Double(budgetBytes), 1) * 1.15
    }

    private var isEmpty: Bool { (points.last?.bytes ?? 0) == 0 }

    var body: some View {
        MobileCard("Bugünün kümülatif kullanımı", systemImage: "chart.xyaxis.line") {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("Zaman", p.date), y: .value("Kullanım", Double(p.bytes)))
                        .foregroundStyle(.linearGradient(colors: [.orange.opacity(0.35), .orange.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Zaman", p.date), y: .value("Kullanım", Double(p.bytes)))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                if budgetBytes > 0 {
                    RuleMark(y: .value("Bütçe", Double(budgetBytes)))
                        .foregroundStyle(.red.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            Text("\(budgetBytes < dailyCapBytes ? "Bütçe" : "Günlük limit") \(Format.bytes(budgetBytes))")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                }
                if dailyCapBytes > budgetBytes {
                    RuleMark(y: .value("Günlük limit", Double(dailyCapBytes)))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(domain: dayStart...dayStart.addingTimeInterval(86_400))
            .chartYScale(domain: 0...max(peak, Double(dailyCapBytes) * 1.05))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().locale(Self.locale))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Format.bytes(UInt64(max(0, v)))) }
                    }
                }
            }
            .frame(height: 180)
            .overlay {
                if !loaded {
                    ProgressView().controlSize(.small)
                } else if isEmpty {
                    Text("Bugün henüz mobil veri kullanılmadı.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bugünün kümülatif mobil kullanım grafiği")
            .accessibilityValue(isEmpty ? "Kullanım yok" : "Şu ana kadar \(Format.bytes(points.last?.bytes ?? 0))")
        }
    }
}
