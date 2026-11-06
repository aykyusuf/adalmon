import SwiftUI

/// Tablodaki uygulama hücresi: simge + ad.
struct AppNameCell: View {
    let row: AppUsageTableRow

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppCatalog.shared.icon(for: row.id))
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(row.name)
                .lineLimit(1)
        }
    }
}
