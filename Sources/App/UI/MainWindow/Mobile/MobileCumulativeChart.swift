import SwiftUI

/// Bugünün kümülatif mobil kullanımı; bütçe (ve farklıysa günlük limit) çizgisiyle. İmleç gelince o saate kadarki toplam.
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

    private var rules: [ChartRule] {
        var out: [ChartRule] = []
        if budgetBytes > 0 {
            out.append(ChartRule(name: "Bütçe", value: Double(budgetBytes), color: .red.opacity(0.8),
                                 label: "\(budgetBytes < dailyCapBytes ? "Bütçe" : "Günlük limit") \(Format.bytes(budgetBytes))"))
        }
        if dailyCapBytes > budgetBytes {
            out.append(ChartRule(name: "Günlük limit", value: Double(dailyCapBytes), color: .secondary.opacity(0.6), dash: [2, 4], lineWidth: 1))
        }
        return out
    }

    var body: some View {
        MobileCard("Bugünün kümülatif kullanımı", systemImage: "chart.xyaxis.line") {
            InteractiveLineChart(
                lines: [ChartLine(name: "Kullanım", color: .orange, points: points.map { ChartPoint(date: $0.date, value: Double($0.bytes)) })],
                xDomain: dayStart...dayStart.addingTimeInterval(86_400),
                yDomain: 0...max(peak, Double(dailyCapBytes) * 1.05),
                yLabel: { Format.bytes(UInt64(max(0, $0))) },
                timeLabel: { $0.formatted(.dateTime.hour().minute().locale(Self.locale)) },
                yAxisPosition: .trailing,
                xAxisValues: .stride(by: .hour, count: 6),
                xLabel: { $0.formatted(.dateTime.hour().locale(Self.locale)) },
                rules: rules,
                lineWidth: 2,
                accessibilityTitle: "Bugünün kümülatif mobil kullanım grafiği",
                accessibilitySummary: isEmpty ? "Kullanım yok" : "Şu ana kadar \(Format.bytes(points.last?.bytes ?? 0))")
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
        }
    }
}
