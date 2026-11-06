import SwiftUI

struct AppKeyRow: View {
    let app: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppCatalog.shared.icon(for: app))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(AppCatalog.shared.name(for: app)).lineLimit(1)
            Spacer()
            Button("Kaldır", systemImage: "minus.circle", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }
}
