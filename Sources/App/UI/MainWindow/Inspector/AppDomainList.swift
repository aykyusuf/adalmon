import SwiftUI

/// Alan adı listesi (çubuklu): bugün / son 7 gün. Alan adı yoksa kısa bir açıklama gösterir.
struct AppDomainList: View {
    enum Range: String, CaseIterable, Identifiable {
        case today = "Bugün"
        case week = "7 gün"

        var id: String { rawValue }
    }

    let detail: AppDetail
    let hasTraffic: Bool
    @State private var range = Range.today

    private var rows: [UsageStore.DomainBytes] {
        (range == .today ? detail.domainsToday : detail.domains7d).filter { $0.bytes > 0 }
    }

    /// Hiç gerçek alan adı yok (yalnızca "Bilinmeyen" ya da boş): proxy üzerinden geçen akışlar.
    private var lacksDomains: Bool {
        let all = detail.domains7d + detail.domainsToday
        return hasTraffic && all.allSatisfy { $0.name == "Bilinmeyen" }
    }

    var body: some View {
        InspectorSection(title: "Alan adları") {
            Picker("Dönem", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        } content: {
            if rows.isEmpty {
                Text(range == .today ? "Bugün için alan adı kaydı yok." : "Son 7 günde alan adı kaydı yok.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let peak = Double(rows.map(\.bytes).max() ?? 1)
                VStack(spacing: 10) {
                    ForEach(rows.prefix(8), id: \.name) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text(Format.bytes(row.bytes))
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            UsageBar(fraction: Double(row.bytes) / peak, tint: .accentColor.opacity(0.75), height: 4)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if lacksDomains {
                Label("Alan adı okunamadı (SpoofDPI açıkken ilk istekten alınır; bu bağlantılarda bulunamadı).", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
