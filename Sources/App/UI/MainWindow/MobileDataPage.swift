import SwiftUI

/// "Mobil veri": bugünkü mobil kullanım / kota göstergesi, Wi-Fi toplamı ve mobil veriyi en çok kullanan uygulamalar.
struct MobileDataPage: View {
    let data: PanelData

    var body: some View {
        let used = data.mobileToday
        let cap = data.dailyCapBytes
        let fraction = cap == 0 ? 0 : min(1, Double(used) / Double(cap))
        let tint: Color = fraction >= 1 ? .red : (fraction >= 0.8 ? .orange : .green)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: MainSection.mobile.title) {
                    ConnectionBadge(medium: data.medium, isMobile: data.isMobile, interfaceName: data.interfaceName)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Bugün mobil").font(.headline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Format.bytes(used))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(fraction >= 0.8 ? tint : .primary)
                            .contentTransition(.numericText())
                        Text("/ \(Format.bytes(cap)) günlük kota · \(Format.percent(fraction))")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Gauge(value: fraction) {
                        Text("Günlük mobil kota")
                    }
                    .gaugeStyle(.linearCapacity)
                    .labelsHidden()
                    .tint(tint)
                    .accessibilityValue("Mobil veri \(Format.bytes(used)) / \(Format.bytes(cap)), yüzde \(Int(fraction * 100))")
                    Text("Kotayı Ayarlar › Mobil veri bölümünden değiştirebilirsin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))

                HStack(spacing: 16) {
                    statCard("Wi-Fi bugün", value: Format.bytes(data.wifiToday), systemImage: "wifi")
                    statCard("Sistem/diğer mobil", value: Format.bytes(data.unattributedMobile), systemImage: "gearshape.2",
                             help: "Arayüz sayacı ile uygulamalara yazılan trafik arasındaki fark (DNS, sistem, VPN vb.)")
                }

                topMobileApps
            }
            .padding(24)
        }
    }

    private func statCard(_ title: String, value: String, systemImage: String, help: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
        .help(help)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var topMobileApps: some View {
        let apps = data.today.filter { $0.mobileBytes > 0 }.sorted { $0.mobileBytes > $1.mobileBytes }.prefix(8)
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mobil veriyi en çok kullananlar").font(.headline).foregroundStyle(.secondary)
                ForEach(apps) { usage in
                    HStack(spacing: 8) {
                        Image(nsImage: AppCatalog.shared.icon(for: usage.app))
                            .resizable()
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                        Text(AppCatalog.shared.name(for: usage.app)).lineLimit(1)
                        Spacer()
                        Text(Format.bytes(usage.mobileBytes)).monospacedDigit().foregroundStyle(.orange)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
        }
    }
}
