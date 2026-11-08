import SwiftUI

struct CPUPanelView: View {
    let model: CPUPanelModel
    let isMeasuringProcesses: Bool
    let actions: PanelActions
    let opensMainWindow: Bool
    var maxHeight: CGFloat?
    var previewHover: Double?

    var body: some View {
        PanelScaffold(kind: .cpu, actions: actions, opensMainWindow: opensMainWindow, subtitle: model.topologyText, maxHeight: maxHeight) {
            PanelCard(tint: .blue) {
                VStack(alignment: .leading, spacing: 10) {
                    BigValueHeader(value: model.bigValue, caption: "toplam kullanım", tint: loadTint) {
                        VStack(alignment: .trailing, spacing: 3) {
                            legend("Kullanıcı", model.userText, .blue)
                            legend("Sistem", model.systemText, .red)
                        }
                    }
                    SplitBar(first: model.userFraction, second: model.systemFraction, firstTint: .blue, secondTint: .red)
                    PanelHoverSparkline(series: model.series, tint: .blue, previewHover: previewHover)
                }
            }
            if !model.cores.isEmpty {
                PanelCard {
                    VStack(alignment: .leading, spacing: 8) {
                        PanelGroupTitle(title: "Çekirdekler", trailing: "P performans · E verimlilik")
                        CoreBars(cores: model.cores)
                    }
                }
            }
            PanelCard {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(zip(["1 dk", "5 dk", "15 dk"], model.loadAverages)), id: \.0) { PanelStatTile(title: "Yük \($0.0)", value: $0.1) }
                    if let avg = model.temperatureAverage {
                        PanelStatTile(title: "Sıcaklık", value: avg, caption: model.temperatureMax.map { "en sıcak \($0)" }, tint: .orange)
                    }
                }
            }
            if let uptime = model.uptimeText {
                PanelCard {
                    VStack(alignment: .leading, spacing: 3) {
                        PanelValueRow(title: "Açık kalma süresi", value: uptime, bold: true)
                        if let boot = model.bootText { Text(boot).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 6) {
                    PanelGroupTitle(title: "En çok CPU kullananlar")
                    TopProcessList(processes: model.processes, tint: .blue, isMeasuring: isMeasuringProcesses) { _ in actions.openProcesses(.processes) }
                }
            }
        } footer: {
            PanelFooterButton(title: opensMainWindow ? "Süreçler'de aç" : "Etkinlik Monitörü'nde aç",
                              systemImage: "waveform.path.ecg") { actions.openProcesses(.processes) }
        }
    }

    private var loadTint: Color { model.total >= 0.9 ? .red : (model.total >= 0.75 ? .orange : .primary) }

    private func legend(_ title: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}

/// Çekirdek başına dikey çubuklar (P mavi, E turkuaz).
struct CoreBars: View {
    let cores: [CPUPanelModel.Core]

    var body: some View {
        HStack(alignment: .bottom, spacing: cores.count > 12 ? 3 : 5) {
            ForEach(cores) { core in
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(.primary.opacity(0.1))
                            .overlay(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill((core.isEfficiency ? Color.mint : Color.blue).gradient)
                                    .frame(height: max(core.fraction > 0.01 ? 3 : 0, geo.size.height * core.fraction))
                            }
                    }
                    .frame(height: 46)
                    Text(core.label).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Çekirdek \(core.label)")
                .accessibilityValue(Format.percent(core.fraction))
            }
        }
    }
}
