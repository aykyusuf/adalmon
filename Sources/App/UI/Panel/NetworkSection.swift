import SwiftUI

/// Ağ bölümü: anlık ↓/↑ hız başlığı ve (açıksa) son 60 sn grafiği.
struct NetworkSection: View {
    let data: PanelData
    @Binding var config: PanelConfig

    var body: some View {
        let collapsed = config.isCollapsed(.networkChart)
        let height = config.chartHeight.points
        VStack(alignment: .leading, spacing: 5) {
            PanelSectionHeader(title: "Ağ", isCollapsed: collapsed, isCollapsible: height != nil) {
                withAnimation(.snappy) { config.toggleCollapsed(.networkChart) }
            } accessory: {
                let n = data.snapshot?.network
                HStack(spacing: 8) {
                    Label(Format.rate(n?.downloadBytesPerSecond ?? 0), systemImage: "arrow.down")
                        .foregroundStyle(.blue)
                    Label(Format.rate(n?.uploadBytesPerSecond ?? 0), systemImage: "arrow.up")
                        .foregroundStyle(.orange)
                }
                .font(.caption.weight(.semibold))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("İndirme \(Format.rate(n?.downloadBytesPerSecond ?? 0)), yükleme \(Format.rate(n?.uploadBytesPerSecond ?? 0))")
            }
            if let height, !collapsed {
                NetworkChart(down: data.downHistory, up: data.upHistory)
                    .frame(height: height)
            }
        }
    }
}
