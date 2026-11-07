import Charts
import SwiftUI

/// Ana penceredeki zaman serisi grafikleri için ortak, etkileşimli alan+çizgi grafiği: imleç gelince dikey çizgi, işaret
/// noktaları ve tüm serilerin değerlerini + zamanı gösteren kutu çıkar (tıklama gerekmez). Eksen ve renk ayarları
/// çağıran grafikten gelir; yeniden çizim yalnızca imlecin en yakın örneği değişince olur.
struct InteractiveLineChart: View {
    let lines: [ChartLine]
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    /// Eksen etiketi ve ipucu değeri.
    let yLabel: (Double) -> String
    /// İpucunun başlığı (imlecin zamanı).
    let timeLabel: (Date) -> String
    /// Eksen etiketi ipucundakinden farklıysa (örn. eksende ondalıksız yüzde).
    var yAxisLabel: ((Double) -> String)?
    var yAxisPosition: AxisMarkPosition = .leading
    var yAxisValues: AxisMarkValues = .automatic(desiredCount: 4)
    /// nil ise x ekseni (etiket ve ızgara) çizilmez.
    var xAxisValues: AxisMarkValues?
    var xLabel: (Date) -> String = { $0.formatted(.dateTime.hour().minute()) }
    var rules: [ChartRule] = []
    var lineWidth: CGFloat = 1.6
    /// Küçük kartlardaki grafikler: tek satırlık ipucu, grafik içine sığdırılır.
    var compact = false
    var accessibilityTitle: LocalizedStringKey = "Grafik"
    var accessibilitySummary = ""
    /// İmleç grafiğe girince/çıkınca (canlı grafiklerde veriyi dondurmak için).
    var onHoverChange: ((Bool) -> Void)?

    @State private var hover: Date?

    var body: some View {
        let readout = hover.flatMap { ChartReadout.make(lines: lines, at: $0, title: timeLabel, value: yLabel) }
        Chart {
            ForEach(lines) { line in
                ForEach(line.points) { p in
                    // Alan, y ekseninin alt sınırından başlar: eksen 0'dan başlamıyorsa (ör. boş alan 12–15 GB) grafik dışına taşmaz.
                    AreaMark(x: .value("Zaman", p.date), yStart: .value(line.name, yDomain.lowerBound),
                             yEnd: .value(line.name, max(yDomain.lowerBound, p.value)), series: .value("Seri", line.name))
                        .foregroundStyle(.linearGradient(colors: [line.color.opacity(lines.count > 1 ? 0.22 : 0.4), line.color.opacity(0.03)],
                                                         startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Zaman", p.date), y: .value(line.name, p.value), series: .value("Seri", line.name))
                        .foregroundStyle(line.color)
                        .lineStyle(StrokeStyle(lineWidth: lineWidth))
                        .interpolationMethod(.monotone)
                }
            }
            ForEach(rules) { rule in
                RuleMark(y: .value(rule.name, rule.value))
                    .foregroundStyle(rule.color)
                    .lineStyle(StrokeStyle(lineWidth: rule.lineWidth, dash: rule.dash))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        if let label = rule.label { Text(label).font(.caption2).foregroundStyle(rule.color) }
                    }
            }
            if let readout { ChartSelectionMarks(readout: readout, compact: compact) }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: yAxisPosition, values: yAxisValues) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text((yAxisLabel ?? yLabel)(v)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues ?? .automatic(desiredCount: 1)) { value in
                if xAxisValues != nil {
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Date.self) { Text(xLabel(d)) }
                    }
                }
            }
        }
        .chartPointer(as: Date.self, pointerMoved)
        .onChange(of: hover != nil) { onHoverChange?(hover != nil) }
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilitySummary)
    }

    /// İmleci en yakın örneğe oturtur; yalnızca örnek değişince durum yazar.
    private func pointerMoved(_ date: Date?) {
        guard let date, let primary = lines.first(where: { !$0.points.isEmpty }),
              let i = ChartNearest.index(in: primary.points, to: date, tolerance: ChartNearest.tolerance(for: primary.points)) else {
            if hover != nil { hover = nil }
            return
        }
        let snapped = primary.points[i].date
        if hover != snapped { hover = snapped }
    }
}
