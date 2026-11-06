import SwiftUI

/// Mobil veride engellenen uygulamaların listesi; buradan engel kaldırılır.
struct MobileBlockedCard: View {
    let model: AppModel
    let blocked: [String]

    var body: some View {
        MobileCard("Mobilde engellenenler", systemImage: "hand.raised") {
            if blocked.isEmpty {
                Text("Yok. Ağ kullanımı sayfasındaki ✋ düğmesiyle ya da bildirimden ekleyebilirsin.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(blocked, id: \.self) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: AppCatalog.shared.icon(for: app))
                                .resizable()
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                            Text(AppCatalog.shared.name(for: app))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Button("Kaldır") { model.setBlocked(app, false) }
                        }
                    }
                }
            }
        }
    }
}
