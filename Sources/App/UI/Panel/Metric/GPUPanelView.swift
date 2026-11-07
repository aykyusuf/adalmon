import SwiftUI

struct GPUPanelView: View {
    let model: GPUPanelModel
    let isMeasuringProcesses: Bool
    let actions: PanelActions
    let opensMainWindow: Bool
    var maxHeight: CGFloat?
    var previewHover: Double?

    var body: some View {
        PanelScaffold(kind: .gpu, actions: actions, opensMainWindow: opensMainWindow,
                      subtitle: model.hasData ? nil : "GPU okunamıyor", maxHeight: maxHeight) {
            PanelCard(tint: .purple) {
                VStack(alignment: .leading, spacing: 10) {
                    BigValueHeader(value: model.bigValue, caption: model.loadText == nil ? "meşgul süre" : "gerçek yük (frekans ağırlıklı)") {
                        VStack(alignment: .trailing, spacing: 3) {
                            if let f = model.frequencyText { Text(f).font(.callout.weight(.semibold)).monospacedDigit(); Text("frekans").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    PanelHoverSparkline(series: model.series, tint: .purple, previewHover: previewHover)
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        PanelStatTile(title: "Gerçek yük", value: model.loadText ?? "—", caption: "frekansa göre")
                        PanelStatTile(title: "Meşgul", value: model.busyText, caption: "süre")
                        PanelStatTile(title: "Sıcaklık", value: model.temperature ?? "—", tint: .orange)
                        if let m = model.memory { PanelStatTile(title: "Bellek", value: m) }
                    }
                    if let f = model.frequencyFraction {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text("Frekans").font(.caption2).foregroundStyle(.secondary); Spacer(); Text(model.frequencyText ?? "").font(.caption2).monospacedDigit().foregroundStyle(.secondary) }
                            UsageBar(fraction: f, tint: .purple, height: 5)
                        }
                    }
                    if model.rendererText != nil || model.tilerText != nil {
                        HStack(spacing: 8) {
                            if let r = model.rendererText { PanelStatTile(title: "Çizim", value: r) }
                            if let t = model.tilerText { PanelStatTile(title: "Döşeme", value: t) }
                        }
                    }
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 6) {
                    PanelGroupTitle(title: "GPU kullanan uygulamalar")
                    TopProcessList(processes: model.processes, tint: .purple, emptyText: "Şu an GPU kullanan uygulama yok",
                                   isMeasuring: isMeasuringProcesses) { _ in actions.openProcesses(.processes) }
                }
            }
        } footer: {
            PanelFooterButton(title: opensMainWindow ? "Süreçler'de aç" : "Etkinlik Monitörü'nde aç",
                              systemImage: "waveform.path.ecg") { actions.openProcesses(.processes) }
        }
    }
}
