import SwiftUI

/// Renk noktası + ad + değer: renge ek olarak metinle de ayırt edilir.
struct LegendValue: View {
    let color: Color
    let title: String
    let bytes: UInt64

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(title).foregroundStyle(.secondary)
            Text(Format.bytes(bytes)).monospacedDigit().fontWeight(.medium)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}
