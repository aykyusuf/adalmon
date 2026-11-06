import SwiftUI

/// Rapordaki alan adı satırı: ad, bayt ve en büyüğe göre ince çubuk.
struct HistoryReportDomainRow: View {
    let domain: HistoryDomainBytes
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(domain.name).lineLimit(1)
                Spacer(minLength: 8)
                Text(Format.bytes(domain.bytes)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            UsageBar(fraction: fraction, tint: .indigo, height: 3)
        }
        .accessibilityElement(children: .combine)
    }
}
