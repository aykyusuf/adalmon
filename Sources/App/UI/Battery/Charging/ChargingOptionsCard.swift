import SwiftUI

struct ChargingOptionsCard: View {
    @Bindable var model: ChargingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Adalmon kapanınca şarj sınırını kaldır", isOn: $model.restoreOnQuit)
            Text(model.restoreOnQuit
                 ? "Uygulamadan çıkınca normal şarja dönülür; açılışta sınır yeniden uygulanır."
                 : "Uygulama kapalıyken de yardımcı sınırı uygulamaya devam eder.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .batteryCard()
    }
}
