import SwiftUI

/// Başlık, "kullanılan / limit", doluluk çubuğu ve bir ek satır.
struct QuotaGauge: View {
    let title: String
    let used: UInt64
    let cap: UInt64
    let detail: String?

    var body: some View {
        let fraction = cap == 0 ? 0 : min(1, Double(used) / Double(cap))
        let tint: Color = fraction >= 1 ? .red : (fraction >= 0.8 ? .orange : .green)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text("\(Format.bytes(used)) / \(Format.bytes(cap))")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                Text(Format.percent(fraction))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(fraction >= 0.8 ? tint : .secondary)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            UsageBar(fraction: fraction, tint: tint, height: 8)
            if let detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
