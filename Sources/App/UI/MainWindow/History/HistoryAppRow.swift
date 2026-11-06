import SwiftUI

/// Uygulama satırı; açılınca o dilimdeki alan adı grupları yüklenir.
struct HistoryAppRow: View {
    let app: HistoryAppBytes
    let fraction: Double
    let loader: HistoryDetailLoader
    @State private var isExpanded = false
    @State private var domains: [HistoryDomainBytes] = []

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(domains) { domain in
                HStack {
                    Text(domain.name).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.bytes(domain.bytes)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if domains.isEmpty {
                Text("Alan adı kaydı yok").font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: AppCatalog.shared.icon(for: app.app))
                    .resizable()
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(AppCatalog.shared.name(for: app.app)).lineLimit(1)
                        Spacer(minLength: 8)
                        if app.mobile > 0 {
                            Label(Format.bytes(app.mobile), systemImage: "antenna.radiowaves.left.and.right")
                                .font(.caption)
                                .foregroundStyle(MediumStyle.mobileColor)
                                .monospacedDigit()
                        }
                        Text(Format.bytes(app.bytes)).monospacedDigit().fontWeight(.medium)
                    }
                    UsageBar(fraction: fraction, tint: .accentColor, height: 4)
                }
            }
        }
        .task(id: isExpanded) {
            guard isExpanded else { return }
            domains = await loader.domains(app: app.app)
        }
    }
}
