import SwiftUI

/// Bugünün özeti: toplam, ↓↑, mobil/Wi-Fi payı ve dünle karşılaştırma.
struct OverviewTodayCard: View {
    let summary: TodaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bugün", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Format.bytes(summary.total))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                HStack(spacing: 10) {
                    Label(Format.bytes(summary.down), systemImage: "arrow.down").foregroundStyle(.blue)
                    Label(Format.bytes(summary.up), systemImage: "arrow.up").foregroundStyle(.orange)
                }
                .font(.callout.weight(.medium))
                .monospacedDigit()
            }
            MediumSplitBar(mobile: summary.mobile, wifi: summary.wifi)
            HStack(spacing: 16) {
                LegendValue(color: MediumStyle.mobileColor, title: MediumStyle.mobileName, bytes: summary.mobile)
                LegendValue(color: MediumStyle.wifiColor, title: MediumStyle.wifiName, bytes: summary.wifi)
            }
            Divider()
            YesterdayComparison(today: summary.total, yesterday: summary.yesterday)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
