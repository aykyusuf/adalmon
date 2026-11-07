import SwiftUI

/// "En çok kullanan uygulamalar" listesi: simge + ad + çubuk + değer. Satıra tıklamak ayrıntı sayfasını açar.
struct TopProcessList: View {
    let processes: [TopProcess]
    let tint: Color
    var emptyText = "Şu an kayda değer etkinlik yok"
    var isMeasuring = false
    var onSelect: ((TopProcess) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if processes.isEmpty {
                Text(isMeasuring ? "Ölçülüyor…" : emptyText)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(processes) { p in
                    Button { onSelect?(p) } label: { row(p) }
                        .buttonStyle(.plain)
                        .disabled(onSelect == nil)
                }
            }
        }
    }

    private func row(_ p: TopProcess) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: ResourceDisplay.icon(p.key))
                .resizable().scaledToFit().frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.callout).lineLimit(1)
                UsageBar(fraction: p.fraction, tint: tint, height: 3)
            }
            Text(p.valueText)
                .font(.callout.weight(.medium)).monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.name), \(p.valueText)")
    }
}
