import SwiftUI

/// Canlı ağ hızı ve son 60 sn grafiği (kompakt).
struct OverviewNetworkCard: View {
    let data: PanelData
    var secondsPerPoint = 2

    var body: some View {
        let network = data.snapshot?.network
        let down = Format.rate(network?.downloadBytesPerSecond ?? 0)
        let up = Format.rate(network?.uploadBytesPerSecond ?? 0)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Ağ", systemImage: "network")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 14) {
                    Label(down, systemImage: "arrow.down").foregroundStyle(.blue)
                    Label(up, systemImage: "arrow.up").foregroundStyle(.orange)
                }
                .font(.headline)
                .monospacedDigit()
            }
            Text("Son 60 sn: ↓\(Format.bytes(data.downLast60)) ↑\(Format.bytes(data.upLast60))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            TrafficChart(down: data.downHistory, up: data.upHistory, secondsPerPoint: secondsPerPoint)
                .frame(height: 90)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ağ, indirme \(down), yükleme \(up)")
    }
}
