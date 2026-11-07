import SwiftUI

/// Pil › Şarj sekmesi (Faz 4): şarj sınırı, düşük güç modu, MagSafe LED. Ana şalter varsayılan KAPALI.
struct ChargingTab: View {
    let model: ChargingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChargingWarningCard()
            ChargingMasterCard(model: model)
            if model.featureEnabled {
                ChargingHelperCard(model: model)
                if model.installState.isEnabled {
                    // Şarj sınırı kartı bilerek yok: bu Mac'te şarjı durduran SMC anahtarı yok, kullanıcı "şarj sınırı olmasın" dedi.
                    LowPowerModeCard(model: model)
                    if model.status?.supportsMagSafeLED == true { MagSafeLEDCard(model: model) }
                    ChargingOptionsCard(model: model)
                }
                ChargingKillSwitch(model: model)
            }
        }
        .task(id: model.featureEnabled) {
            // Yoklama yalnızca sekme görünürken ve ana şalter açıkken çalışır.
            guard model.featureEnabled else { return }
            while !Task.isCancelled {
                await model.refreshStatus()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
