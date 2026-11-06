import SwiftUI

struct TopAppButton: View {
    let row: TopAppRow
    let fraction: Double
    let router: SettingsRouter

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(nsImage: AppCatalog.shared.icon(for: row.id))
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.name).lineLimit(1)
                        Spacer(minLength: 8)
                        if row.mobile > 0 {
                            Label(Format.bytes(row.mobile), systemImage: "antenna.radiowaves.left.and.right")
                                .font(.caption)
                                .foregroundStyle(MediumStyle.mobileColor)
                                .monospacedDigit()
                        }
                        Text(Format.bytes(row.bytes)).monospacedDigit().fontWeight(.medium)
                    }
                    UsageBar(fraction: fraction, tint: .accentColor, height: 4)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.name), \(Format.bytes(row.bytes))")
        .accessibilityHint("Ağ kullanımı sayfasında bu uygulamayı seçer")
    }

    private func open() {
        router.selectedAppID = row.id
        router.selectedMainSection = .network
    }
}
