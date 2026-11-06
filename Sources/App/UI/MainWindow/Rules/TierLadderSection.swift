import SwiftUI

/// Kademeli limit: uyar → yavaşlat → kes. Kullanım yüzdesi günlük (varsa aylık) mobil limite göredir.
struct TierLadderSection: View {
    let model: AppModel
    @Bindable var prefs: Preferences

    var body: some View {
        RulesCard(title: "Kademeli limit", systemImage: "chart.line.uptrend.xyaxis",
                  subtitle: "Mobil kullanım yüzdesi arttıkça önce uyarır, sonra diğer uygulamaları yavaşlatır, en sonda en çok tüketenleri keser.") {
            Toggle("Kademeli limiti kullan", isOn: $prefs.tierLadder.enabled)
            if prefs.tierLadder.enabled {
                TierLadderFields(model: model, prefs: prefs)
            }
        }
        .onChange(of: prefs.tierLadder) { model.rulesDidChange() }
    }
}
