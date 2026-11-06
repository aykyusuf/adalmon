import Charts
import SwiftUI

/// Tek satırlık yığılmış çubuk: toplamın mobil / Wi-Fi payı.
struct MediumSplitBar: View {
    let mobile: UInt64
    let wifi: UInt64

    var body: some View {
        Chart {
            BarMark(x: .value("Bayt", Double(wifi)), y: .value("Ağ", ""), stacking: .normalized)
                .foregroundStyle(by: .value("Ağ", MediumStyle.wifiName))
            BarMark(x: .value("Bayt", Double(mobile)), y: .value("Ağ", ""), stacking: .normalized)
                .foregroundStyle(by: .value("Ağ", MediumStyle.mobileName))
        }
        .chartForegroundStyleScale(MediumStyle.scale)
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.background(Color.primary.opacity(0.08), in: .capsule).clipShape(.capsule) }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}
