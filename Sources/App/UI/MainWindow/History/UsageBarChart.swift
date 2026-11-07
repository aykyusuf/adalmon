import Charts
import SwiftUI

/// Mobil / Wi-Fi yığılmış çubuk grafiği. Bir çubuğa gelmek/tıklamak onu seçer (`chartXSelection`); seçim son seçilen çubukta kalır.
struct UsageBarChart: View {
    let bars: [HistoryBar]
    @Binding var selectedID: String?
    @State private var hoverID: String?

    var body: some View {
        let axisLabels = Dictionary(uniqueKeysWithValues: bars.compactMap { bar in bar.axisLabel.map { (bar.id, $0) } })
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Zaman", bar.id), y: .value("Veri", Double(bar.other)))
                    .foregroundStyle(by: .value("Ağ", MediumStyle.wifiName))
                    .opacity(opacity(bar))
                BarMark(x: .value("Zaman", bar.id), y: .value("Veri", Double(bar.mobile)))
                    .foregroundStyle(by: .value("Ağ", MediumStyle.mobileName))
                    .opacity(opacity(bar))
            }
            if let hovered = bars.first(where: { $0.id == hoverID }) {
                ChartBarSelectionMarks(x: hovered.id, title: hovered.label, rows: tooltipRows(hovered))
            }
        }
        .chartForegroundStyleScale(MediumStyle.scale)
        .chartLegend(.hidden)
        .chartXSelection(value: $hoverID)
        .chartXAxis {
            AxisMarks(values: bars.filter { $0.axisLabel != nil }.map(\.id)) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let text = axisLabels[id] { Text(text) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Format.bytes(UInt64(max(0, v)))) }
                }
            }
        }
        .onChange(of: hoverID) {
            if let hoverID { selectedID = hoverID }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kullanım grafiği")
        .accessibilityValue(summary)
        .accessibilityHint("Ayrıntıyı aşağıdaki karttan önceki ve sonraki düğmeleriyle gezebilirsin")
    }

    private func tooltipRows(_ bar: HistoryBar) -> [ChartTooltipRow] {
        [ChartTooltipRow(name: MediumStyle.mobileName, color: MediumStyle.mobileColor, text: Format.bytes(bar.mobile)),
         ChartTooltipRow(name: MediumStyle.wifiName, color: MediumStyle.wifiColor, text: Format.bytes(bar.other)),
         ChartTooltipRow(name: "Toplam", color: .secondary, text: Format.bytes(bar.total))]
    }

    private func opacity(_ bar: HistoryBar) -> Double {
        selectedID == nil || selectedID == bar.id ? 1 : 0.5
    }

    private var summary: String {
        guard let top = bars.max(by: { $0.total < $1.total }), top.total > 0 else { return "Kayıt yok" }
        return "En yüksek: \(top.label), \(Format.bytes(top.total))"
    }
}
