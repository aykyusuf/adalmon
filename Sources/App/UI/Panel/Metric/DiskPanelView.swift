import SwiftUI

struct DiskPanelView: View {
    let model: DiskPanelModel
    var isMeasuringWriters = false
    let actions: PanelActions
    let opensMainWindow: Bool
    var maxHeight: CGFloat?
    var previewHover: Double?

    var body: some View {
        PanelScaffold(kind: .disk, actions: actions, opensMainWindow: opensMainWindow,
                      subtitle: model.hasData ? "\(model.totalText) toplam" : nil, maxHeight: maxHeight) {
            PanelCard(tint: .indigo) {
                VStack(alignment: .leading, spacing: 10) {
                    BigValueHeader(value: model.freeText, caption: "boş alan") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.percent(model.usedFraction)).font(.callout.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(model.usedFraction > 0.9 ? Color.red : Color.primary)
                            Text("\(model.usedText) dolu").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    UsageBar(fraction: model.usedFraction, tint: model.usedFraction > 0.9 ? .red : (model.usedFraction > 0.8 ? .orange : .indigo), height: 8)
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    rateBlock("Okuma", model.readText, model.readSeries, .cyan)
                    rateBlock("Yazma", model.writeText, model.writeSeries, .orange)
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 6) {
                    PanelGroupTitle(title: "En çok yazanlar", trailing: "son 1 saat")
                    TopProcessList(processes: model.writers, tint: .orange, emptyText: "Son 1 saatte kayda değer yazma yok",
                                   isMeasuring: isMeasuringWriters) { _ in
                        actions.openProcesses(.disk)
                    }
                }
            }
        } footer: {
            PanelFooterButton(title: opensMainWindow ? "Büyüyen klasörler" : "Etkinlik Monitörü'nde aç",
                              systemImage: opensMainWindow ? "folder.badge.gearshape" : "waveform.path.ecg") { actions.openProcesses(.disk) }
        }
    }

    private func rateBlock(_ title: String, _ value: String, _ series: PanelSeries, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: "circle.fill").labelStyle(PanelTitleLabelStyle(tint: tint)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            }
            PanelHoverSparkline(series: series, tint: tint, height: 40, previewHover: previewHover)
        }
    }
}
