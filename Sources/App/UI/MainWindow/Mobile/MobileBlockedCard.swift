import SwiftUI

/// Elle engellenen uygulamalar (Mobilde / Wi-Fi'de / Her yerde rozetiyle); buradan engel kaldırılır.
struct MobileBlockedCard: View {
    let model: AppModel
    let blocked: [BlockedAppEntry]

    var body: some View {
        MobileCard("Engellenenler", systemImage: "hand.raised") {
            if blocked.isEmpty {
                Text("Yok. Ağ kullanımı sayfasındaki ✋ düğmesiyle ya da bildirimden ekleyebilirsin.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(blocked) { entry in
                        HStack(spacing: 8) {
                            Image(nsImage: AppCatalog.shared.icon(for: entry.app))
                                .resizable()
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                            Text(AppCatalog.shared.name(for: entry.app))
                                .lineLimit(1)
                            BlockScopeBadge(scope: entry.scope)
                            Spacer(minLength: 8)
                            Button("Kaldır") { model.setBlockScope(entry.app, nil) }
                                .accessibilityLabel("\(AppCatalog.shared.name(for: entry.app)) engelini kaldır")
                        }
                    }
                }
            }
        }
    }
}

/// Engel kapsamı rozeti ("Mobilde" / "Wi-Fi'de" / "Her yerde").
struct BlockScopeBadge: View {
    let scope: BlockScope

    var body: some View {
        Text(scope.title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: .capsule)
            .accessibilityLabel("Kapsam: \(scope.title)")
    }
}
