import SwiftUI

/// Windows Görev Yöneticisi'ndeki gibi başlık + büyük değer ızgarası.
struct PerformanceStatsGrid: View {
    let stats: [PerformanceStat]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16, alignment: .topLeading)], alignment: .leading, spacing: 14) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.title).font(.caption).foregroundStyle(.secondary)
                    Text(stat.value).font(.title3.weight(.medium)).monospacedDigit().lineLimit(2).minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
