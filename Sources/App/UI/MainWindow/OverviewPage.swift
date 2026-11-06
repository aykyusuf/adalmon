import SwiftUI

/// "Genel bakış": CPU/GPU/RAM/Disk için büyük geçmiş grafikleri ve ağ trafiği.
struct OverviewPage: View {
    let data: PanelData

    var body: some View {
        let metrics = SystemMetric.all(data, showTemperatures: true)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: MainSection.overview.title) {
                    ConnectionBadge(medium: data.medium, isMobile: data.isMobile, interfaceName: data.interfaceName)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(metrics) { OverviewMetricCard(metric: $0) }
                }
                OverviewNetworkCard(data: data)
            }
            .padding(24)
        }
    }
}
