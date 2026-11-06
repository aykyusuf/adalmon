import SwiftUI

struct HistoryDetailHeader: View {
    let bar: HistoryBar
    let hasPrevious: Bool
    let hasNext: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bar.label)
                    .font(.headline)
                HStack(spacing: 12) {
                    Text(Format.bytes(bar.total)).monospacedDigit().fontWeight(.medium)
                    LegendValue(color: MediumStyle.mobileColor, title: MediumStyle.mobileName, bytes: bar.mobile)
                    LegendValue(color: MediumStyle.wifiColor, title: MediumStyle.wifiName, bytes: bar.other)
                }
                .font(.callout)
            }
            Spacer()
            ControlGroup {
                Button("Önceki", systemImage: "chevron.left", action: previous).disabled(!hasPrevious)
                Button("Sonraki", systemImage: "chevron.right", action: next).disabled(!hasNext)
            }
            .labelStyle(.iconOnly)
            .controlGroupStyle(.navigation)
        }
    }
}
