import SwiftUI

/// Sistem bölümü: seçili stile göre karo/kart/satır.
struct SystemSection: View {
    let data: PanelData
    @Binding var config: PanelConfig
    @State private var selected: SystemMetric.Kind?

    var body: some View {
        let metrics = SystemMetric.all(data, showTemperatures: config.showTemperatures)
        let collapsed = config.isCollapsed(.system)
        VStack(alignment: .leading, spacing: 5) {
            PanelSectionHeader(title: "Sistem", isCollapsed: collapsed) {
                withAnimation(.snappy) { config.toggleCollapsed(.system) }
            } accessory: {
                if collapsed {
                    Text(metrics.prefix(3).map { "\($0.title) \($0.value)" }.joined(separator: " · "))
                }
            }
            if !collapsed {
                switch config.tileStyle {
                case .compactTiles:
                    tiles(metrics)
                case .cards:
                    SystemGrid(metrics: metrics)
                case .rows:
                    VStack(spacing: 4) {
                        ForEach(metrics) { SystemMetricRow(metric: $0) }
                    }
                }
            }
        }
    }

    private func tiles(_ metrics: [SystemMetric]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(metrics) { metric in
                    SystemTile(metric: metric, isSelected: selected == metric.kind) {
                        withAnimation(.snappy) { selected = selected == metric.kind ? nil : metric.kind }
                    }
                }
            }
            if let selected, let metric = metrics.first(where: { $0.kind == selected }), !metric.detail.isEmpty {
                Label(metric.detail, systemImage: metric.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }
}
