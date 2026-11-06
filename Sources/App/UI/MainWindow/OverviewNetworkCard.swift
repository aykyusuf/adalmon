import SwiftUI

/// Genel bakıştaki ağ kartı: anlık ↓/↑ hız ve eksenli trafik grafiği.
struct OverviewNetworkCard: View {
    let data: PanelData

    var body: some View {
        let network = data.snapshot?.network
        let down = Format.rate(network?.downloadBytesPerSecond ?? 0)
        let up = Format.rate(network?.uploadBytesPerSecond ?? 0)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Ağ", systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 14) {
                    Label(down, systemImage: "arrow.down").foregroundStyle(.blue)
                    Label(up, systemImage: "arrow.up").foregroundStyle(.orange)
                }
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            }
            HStack(spacing: 14) {
                Text("Son 60 sn: ↓\(Format.bytes(data.downLast60)) ↑\(Format.bytes(data.upLast60))")
                Text("Bugün: ↓\(Format.bytes(data.downToday)) ↑\(Format.bytes(data.upToday))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            TrafficChart(down: data.downHistory, up: data.upHistory)
                .frame(height: 180)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ağ, indirme \(down), yükleme \(up)")
    }
}
