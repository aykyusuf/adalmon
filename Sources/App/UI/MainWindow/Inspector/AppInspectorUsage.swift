import SwiftUI

/// Bugünün toplamı, mobil / diğer dağılımı ve son 60 sn.
struct AppInspectorUsage: View {
    let total: UInt64
    let mobile: UInt64
    let last60: UInt64

    private var other: UInt64 { total > mobile ? total - mobile : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.bytes(total))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("bugün")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            splitBar
            HStack(alignment: .top, spacing: 0) {
                stat("Mobil", value: mobile, color: .orange)
                stat("Wi-Fi/diğer", value: other, color: .blue)
                stat("Son 60 sn", value: last60, color: .secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var splitBar: some View {
        let fraction = total == 0 ? 0 : Double(mobile) / Double(total)
        return Capsule()
            .fill(Color.blue.opacity(total == 0 ? 0.15 : 0.55))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: max(mobile > 0 ? 6 : 0, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            .clipShape(.capsule)
            .accessibilityHidden(true)
    }

    private func stat(_ title: String, value: UInt64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value > 0 ? Format.bytes(value) : "–")
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
