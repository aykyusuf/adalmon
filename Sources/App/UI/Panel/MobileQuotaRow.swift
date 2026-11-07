import SwiftUI

/// "Kota" satırı: kullanım / limit, ilerleme çubuğu ve yüzde; varsa altında dolma tahmini ("~21:40 civarı dolar").
struct MobileQuotaRow: View {
    let data: PanelData
    @Environment(\.panelDensity) private var density

    var body: some View {
        let quota = MobileQuotaSummary(data)
        let tint = Self.tint(quota.level)
        let note = quota.etaText()
        let showsNote = note != nil || data.unattributedMobile > 1_000_000
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label("Kota", systemImage: "antenna.radiowaves.left.and.right")
                    .labelStyle(PanelTitleLabelStyle(tint: tint))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(quota.usageText)
                    .font(.caption.weight(.medium))
                    .fixedSize()
                UsageBar(fraction: quota.fraction, tint: tint, height: 6)
                Text(quota.percentText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(quota.level == .normal ? AnyShapeStyle(.primary) : AnyShapeStyle(tint))
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .monospacedDigit()
            .lineLimit(1)
            if showsNote {
                HStack {
                    if let note {
                        Text(note)
                            .foregroundStyle(quota.isUrgent ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                    Spacer(minLength: 4)
                    if data.unattributedMobile > 1_000_000 {
                        Text("Sistem/diğer \(Format.bytes(data.unattributedMobile))")
                            .help("Arayüz sayacı ile uygulamalara yazılan trafik arasındaki fark (DNS, sistem, VPN vb.)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            }
        }
        .padding(.horizontal, density.cardPadding)
        .padding(.vertical, density.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PanelCardBackground(cornerRadius: PanelMetricCard.cornerRadius) }
        .help("Bugün mobil: \(Format.bytes(quota.usedBytes)) / \(Format.bytes(quota.capBytes)) · Wi-Fi bugün \(Format.bytes(data.wifiToday))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mobil kota")
        .accessibilityValue(accessibilityValue(quota))
    }

    private func accessibilityValue(_ quota: MobileQuotaSummary) -> String {
        var parts = ["\(Format.bytes(quota.usedBytes)) / \(Format.bytes(quota.capBytes))", "yüzde \(Int((quota.fraction * 100).rounded()))"]
        if let eta = quota.etaText() { parts.append(eta) }
        return parts.joined(separator: ", ")
    }

    private static func tint(_ level: MobileQuotaSummary.Level) -> Color {
        switch level {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}
