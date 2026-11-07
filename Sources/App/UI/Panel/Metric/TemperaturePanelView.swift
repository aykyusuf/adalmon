import SwiftUI

struct TemperaturePanelView: View {
    let model: TemperaturePanelModel
    @Binding var config: PanelConfig
    let actions: PanelActions
    let opensMainWindow: Bool
    var maxHeight: CGFloat?
    var previewHover: Double?

    private static let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        PanelScaffold(kind: .temperature, actions: actions, opensMainWindow: opensMainWindow,
                      subtitle: model.hasData ? nil : "Sensör okunamıyor", maxHeight: maxHeight) {
            PanelCard(tint: .orange) {
                VStack(alignment: .leading, spacing: 10) {
                    BigValueHeader(value: model.headline, caption: "CPU ortalama", tint: Self.heatTint(model.groups.first?.celsius)) { EmptyView() }
                    PanelHoverSparkline(series: model.series, tint: .orange, previewHover: previewHover)
                }
            }
            if !model.groups.isEmpty {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(model.groups) { g in
                        PanelCard(padding: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 5) {
                                    Circle().fill(Self.heatTint(g.celsius)).frame(width: 7, height: 7).accessibilityHidden(true)
                                    Text(g.title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Text(g.value).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                                UsageBar(fraction: g.celsius / WidgetValues.temperatureFullScale, tint: Self.heatTint(g.celsius), height: 3)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            if !model.sensors.isEmpty {
                PanelCollapsibleCard(id: "temperature.sensors", title: "Sensörler", symbol: "sensor", tint: .orange, config: $config) {
                    Text("\(model.sensors.count)")
                } content: {
                    ForEach(model.sensors.prefix(14)) { s in
                        PanelValueRow(title: s.name, value: s.value, tint: Self.heatTint(s.celsius))
                    }
                    if model.sensors.count > 14 {
                        Text("+\(model.sensors.count - 14) sensör daha").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        } footer: {
            PanelFooterButton(title: opensMainWindow ? "Performans'ı aç" : "Etkinlik Monitörü'nde aç", systemImage: "waveform.path.ecg") {
                actions.openProcesses(.performance)
            }
        }
    }

    static func heatTint(_ celsius: Double?) -> Color {
        guard let celsius else { return .primary }
        return celsius >= 90 ? .red : (celsius >= 75 ? .orange : (celsius >= 60 ? .yellow : .green))
    }
}
