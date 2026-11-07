import SwiftUI

/// "Önemli enerji kullanan uygulamalar": sıraya göre renkli çubuklar (kırmızı / turuncu / sarı) + "Uygulama kullanımını aç".
struct BatteryEnergyAppsCard: View {
    let apps: [BatteryEnergyApp]
    let isLoading: Bool
    @Binding var config: PanelConfig
    let actions: PanelActions
    @State private var timedOut = false

    private var state: ListLoadState { .resolve(isLoading: isLoading, itemCount: apps.count, timedOut: timedOut) }

    /// Sıra rengi: 1. kırmızı, 2. turuncu, sonrası sarı.
    static func rankTint(_ index: Int) -> Color { index == 0 ? .red : (index == 1 ? .orange : .yellow) }

    var body: some View {
        if state != .empty {
            PanelCollapsibleCard(id: "battery.apps", title: "Önemli enerji kullanan uygulamalar", symbol: "bolt.circle", tint: .orange,
                                 config: $config, contentPadding: 0) {
                Text("24 sa")
            } content: {
                SkeletonSwap(isLoading: state == .loading) {
                    VStack(spacing: 0) {
                        ForEach(Array(apps.prefix(5).enumerated()), id: \.element.id) { index, app in
                            if index > 0 { Divider().opacity(0.45).padding(.leading, 44) }
                            EnergyAppRow(app: app, rank: index)
                        }
                    }
                } placeholder: {
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { index in
                            if index > 0 { Divider().opacity(0.45).padding(.leading, 44) }
                            EnergyAppRow(app: .placeholder(index), rank: index, isPlaceholder: true)
                        }
                    }
                }
            } footer: {
                Divider().opacity(0.6)
                Button { actions.openRoute(.battery) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.3.layers.3d").font(.system(size: 11, weight: .medium)).frame(width: 22)
                        Text("Uygulama kullanımını aç").font(.callout)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(.rect)
                }
                .buttonStyle(PanelRowButtonStyle())
            }
            .loadTimeout($timedOut)
        }
    }
}

struct EnergyAppRow: View {
    let app: BatteryEnergyApp
    let rank: Int
    var isPlaceholder = false

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.callout).lineLimit(1).modifier(SkeletonIf(active: isPlaceholder))
                if isPlaceholder {
                    Capsule().fill(.primary.opacity(0.13)).frame(height: 4)
                } else {
                    UsageBar(fraction: app.share, tint: BatteryEnergyAppsCard.rankTint(rank), height: 4)
                }
            }
            Text(Self.percentText(app.share))
                .font(.callout.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .modifier(SkeletonIf(active: isPlaceholder))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), yüzde \(Int((app.share * 100).rounded()))")
    }

    static func percentText(_ share: Double) -> String { "\(Int((max(0, min(1, share)) * 100).rounded()))%" }

    @ViewBuilder
    private var icon: some View {
        if isPlaceholder {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(0.13)).frame(width: 22, height: 22)
        } else {
            Image(nsImage: AppCatalog.shared.icon(for: app.app)).resizable().scaledToFit().frame(width: 22, height: 22).accessibilityHidden(true)
        }
    }
}

extension BatteryEnergyApp {
    static func placeholder(_ index: Int) -> BatteryEnergyApp {
        let names = ["Uygulama adı burada", "Başka uygulama", "Kısa ad"]
        return BatteryEnergyApp(app: "placeholder.\(index)", name: names[index % names.count], share: 0)
    }
}
