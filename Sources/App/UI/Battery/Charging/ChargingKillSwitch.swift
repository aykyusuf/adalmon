import SwiftUI

/// Büyük kapatma düğmesi: sınır kapalı, şarj serbest, LED otomatik, özellik bayrağı kapalı.
struct ChargingKillSwitch: View {
    let model: ChargingModel

    var body: some View {
        Button(role: .destructive) {
            Task { await model.disableEverything() }
        } label: {
            Label("Tümünü kapat / varsayılana dön", systemImage: "power")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .help("Şarj sınırını kaldırır, şarjı serbest bırakır, MagSafe LED'i otomatiğe alır ve bu özelliği kapatır.")
    }
}
