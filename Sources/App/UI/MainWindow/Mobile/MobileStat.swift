import SwiftUI

/// Kart içinde küçük başlık + değer çifti.
struct MobileStat: View {
    let title: String
    let value: String
    var tint: Color = .primary
    var help: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help)
        .accessibilityElement(children: .combine)
    }
}
