import SwiftUI

struct MemoryPanelView: View {
    let model: MemoryPanelModel
    let isMeasuringProcesses: Bool
    let actions: PanelActions
    let opensMainWindow: Bool
    var maxHeight: CGFloat?
    var previewHover: Double?

    var body: some View {
        PanelScaffold(kind: .memory, actions: actions, opensMainWindow: opensMainWindow,
                      subtitle: model.hasData ? "\(model.totalText) toplam" : nil, maxHeight: maxHeight) {
            PanelCard(tint: .green) {
                VStack(alignment: .leading, spacing: 10) {
                    BigValueHeader(value: model.bigValue, caption: "kullanılan · \(model.freeText) boş") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.percent(model.usedFraction)).font(.callout.weight(.semibold)).monospacedDigit()
                            Text("dolu").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    PanelHoverSparkline(series: model.series, tint: .green, previewHover: previewHover)
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Bellek baskısı").font(.callout.weight(.semibold))
                        Spacer()
                        Text(model.pressure.title).font(.callout.weight(.semibold)).foregroundStyle(model.pressureTint)
                    }
                    PressureGauge(pressure: model.pressure, tint: model.tint)
                }
                .accessibilityElement(children: .combine)
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(model.parts) { part in
                        VStack(alignment: .leading, spacing: 3) {
                            PanelValueRow(title: part.title, value: part.value)
                            UsageBar(fraction: part.fraction, tint: tint(part.id), height: 4)
                        }
                        .help(part.help)
                    }
                    Divider().opacity(0.5)
                    VStack(alignment: .leading, spacing: 3) {
                        PanelValueRow(title: "Swap", value: model.swapText)
                        UsageBar(fraction: model.swapFraction, tint: .orange, height: 4)
                    }
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 6) {
                    PanelGroupTitle(title: "En çok bellek kullananlar")
                    TopProcessList(processes: model.processes, tint: .green, isMeasuring: isMeasuringProcesses) { _ in actions.openProcesses(.processes) }
                }
            }
        } footer: {
            PanelFooterButton(title: opensMainWindow ? "Süreçler'de aç" : "Etkinlik Monitörü'nde aç",
                              systemImage: "waveform.path.ecg") { actions.openProcesses(.processes) }
        }
    }

    private func tint(_ id: String) -> Color {
        switch id {
        case "app": .green
        case "wired": .orange
        case "compressed": .purple
        default: .cyan
        }
    }
}

/// Üç bölgeli (normal / uyarı / kritik) baskı göstergesi.
struct PressureGauge: View {
    let pressure: MemoryPanelModel.Pressure
    /// Seviye rengi (kullanıcının bellek renkleri); varsayılan yeşil / turuncu / kırmızı.
    var tint: (MemoryPanelModel.Pressure) -> Color = { $0.tint }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    zone(tint(.normal), active: true)
                    zone(tint(.warning), active: pressure != .normal)
                    zone(tint(.critical), active: pressure == .critical)
                }
                Circle().fill(.white).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(tint(pressure), lineWidth: 3))
                    .offset(x: max(0, min(w - 12, w * markerPosition - 6)))
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private var markerPosition: Double {
        switch pressure { case .normal: 0.16; case .warning: 0.5; case .critical: 0.86 }
    }

    private func zone(_ color: Color, active: Bool) -> some View {
        Capsule().fill(color.opacity(active ? 0.85 : 0.22)).frame(height: 6)
    }
}
