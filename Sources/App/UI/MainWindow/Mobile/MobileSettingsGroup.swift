import SwiftUI

/// "Mobil veri" sayfasının altındaki ayar kartları (Dock modunda ayrı Ayarlar girişi yoktur).
struct MobileSettingsGroup: View {
    let model: AppModel
    let blocked: [BlockedAppEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ayarlar")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)], spacing: 16) {
                MobileSettingsCard(model: model)
                MobileLimitsCard(prefs: model.prefs)
            }
            MobileBlockedCard(model: model, blocked: blocked)
        }
    }
}
