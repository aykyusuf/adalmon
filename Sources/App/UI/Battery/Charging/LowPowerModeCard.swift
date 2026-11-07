import SwiftUI

/// Düşük güç modu (pmset -a lowpowermode). Parlaklığı geri yükleme yok: genel, güvenli bir API bulunmuyor.
struct LowPowerModeCard: View {
    let model: ChargingModel
    @State private var draft = false
    @State private var synced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $draft) {
                Label("Düşük güç modu", systemImage: "leaf.fill").font(.headline)
            }
            .disabled(model.isBusy || model.status == nil)
            Text("Tüm güç kaynakları için macOS düşük güç modunu açar ya da kapatır (pmset). Ekran parlaklığını geri yükleme seçeneği yoktur; macOS'un kendi davranışı geçerlidir.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .batteryCard()
        .onAppear { draft = model.status?.lowPowerMode ?? false; synced = true }
        .onChange(of: model.status?.lowPowerMode) { _, new in
            if let new, new != draft { draft = new }
        }
        .onChange(of: draft) { _, new in
            guard synced, let current = model.status?.lowPowerMode, new != current else { return }
            Task { await model.setLowPowerMode(new) }
        }
    }
}
