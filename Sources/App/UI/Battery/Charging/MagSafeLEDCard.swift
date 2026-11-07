import SwiftUI

/// MagSafe LED rengi. Eşleme bu Mac'te doğrulanmadığından ayrı bir "deneysel" bayrağının arkasında.
struct MagSafeLEDCard: View {
    @Bindable var model: ChargingModel
    @State private var draft = MagSafeLEDMode.auto
    @State private var synced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("MagSafe LED", systemImage: "light.max").font(.headline)
            Toggle("Deneysel: LED rengini denetle", isOn: $model.ledFeatureEnabled)
            if model.ledFeatureEnabled {
                Picker("LED", selection: $draft) {
                    ForEach(MagSafeLEDMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.isBusy)
                Text("Renk eşlemesi (Yeşil/Turuncu/Kapalı) başka açık kaynak araçlardan alındı ve bu Mac'te doğrulanmadı. Beklenmeyen bir renk görürseniz “Otomatik”e dönün ya da “Tümünü kapat”a basın.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .batteryCard()
        .onAppear { draft = model.status?.ledMode ?? .auto; synced = true }
        .onChange(of: draft) { _, new in
            guard synced, new != model.status?.ledMode else { return }
            Task { await model.setLED(new) }
        }
    }
}
