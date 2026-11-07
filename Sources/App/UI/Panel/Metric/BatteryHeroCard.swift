import SwiftUI

/// Pil panelinin üst kartı: büyük renkli yüzde, durum satırı (şimşek), sağda "DOLANA / BİTENE KADAR" süresi, dilimli çubuk.
struct BatteryHeroCard: View {
    let model: BatteryPanelModel

    var body: some View {
        PanelCard(tint: model.tint, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(model.level)")
                                .font(.system(size: 50, weight: .bold, design: .rounded))
                                .foregroundStyle(model.tint.gradient)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("%").font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(model.tint.opacity(0.8))
                        }
                        HStack(spacing: 5) {
                            if model.charging { Image(systemName: "bolt.fill").foregroundStyle(.yellow) }
                            else if model.isPluggedIn { Image(systemName: "powerplug.fill").foregroundStyle(model.tint) }
                            Text(model.statusTitle).font(.callout.weight(.semibold))
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(model.untilLabel).font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary)
                        Text(model.untilValue).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)
                }
                SegmentedCapacityBar(level: model.level, tint: model.tint, charging: model.charging, segments: 20, height: 9)
            }
        }
    }
}
