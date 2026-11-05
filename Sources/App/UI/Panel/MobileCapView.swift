import SwiftUI

/// Günlük mobil veri kotası: başlıkta kullanılan/kota, altta ince çubuk ve Wi-Fi özeti.
struct MobileCapView: View {
    let data: PanelData
    @Binding var config: PanelConfig

    var body: some View {
        let used = data.mobileToday
        let cap = data.dailyCapBytes
        let fraction = cap == 0 ? 0 : min(1, Double(used) / Double(cap))
        let tint: Color = fraction >= 1 ? .red : (fraction >= 0.8 ? .orange : .green)
        let collapsed = config.isCollapsed(.mobileCap)
        VStack(alignment: .leading, spacing: 4) {
            PanelSectionHeader(title: "Bugün mobil", isCollapsed: collapsed) {
                withAnimation(.snappy) { config.toggleCollapsed(.mobileCap) }
            } accessory: {
                Text("\(Format.bytes(used)) / \(Format.bytes(cap))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(fraction >= 0.8 ? tint : .primary)
            }
            if !collapsed {
                UsageBar(fraction: fraction, tint: tint, height: 4)
                HStack {
                    Text("Wi-Fi bugün \(Format.bytes(data.wifiToday))")
                    Spacer()
                    if data.unattributedMobile > 1_000_000 {
                        Text("Sistem/diğer \(Format.bytes(data.unattributedMobile))")
                            .help("Arayüz sayacı ile uygulamalara yazılan trafik arasındaki fark (DNS, sistem, VPN vb.)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("Mobil veri \(Format.bytes(used)) / \(Format.bytes(cap)), yüzde \(Int(fraction * 100))")
    }
}
