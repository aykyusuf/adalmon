import SwiftUI

struct ChargingMasterCard: View {
    @Bindable var model: ChargingModel

    var body: some View {
        Toggle(isOn: $model.featureEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Şarj denetimini etkinleştir").font(.headline)
                Text("Kapalıyken yardımcıya hiçbir çağrı yapılmaz ve ek pil maliyeti yoktur.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .batteryCard()
    }
}
