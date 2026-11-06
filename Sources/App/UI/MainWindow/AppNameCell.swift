import SwiftUI

/// Tablodaki uygulama hücresi: simge + ad. Durum sütunu gizliyken engel/sınır durumu ad yanında küçük simgeyle görünür.
struct AppNameCell: View {
    let row: AppUsageTableRow
    var showsStatusGlyph = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppCatalog.shared.icon(for: row.id))
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if showsStatusGlyph {
                if row.isBlocked {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.red)
                        .imageScale(.small)
                        .help("Mobilde engelli")
                        .accessibilityLabel("Mobilde engelli")
                }
                if row.limitText != nil {
                    Image(systemName: "speedometer")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                        .help(row.limitText ?? "")
                        .accessibilityLabel("Hız sınırlı")
                }
            }
        }
    }
}
