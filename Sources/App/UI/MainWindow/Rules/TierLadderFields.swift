import SwiftUI

struct TierLadderFields: View {
    let model: AppModel
    @Bindable var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: $prefs.tierLadder.warnPercent, in: 1...max(1, prefs.tierLadder.slowPercent)) {
                LabeledContent("Uyar") { Text("%\(prefs.tierLadder.warnPercent)").monospacedDigit() }
            }
            Stepper(value: $prefs.tierLadder.slowPercent, in: prefs.tierLadder.warnPercent...max(prefs.tierLadder.warnPercent, prefs.tierLadder.cutPercent)) {
                LabeledContent("Yavaşlat") { Text("%\(prefs.tierLadder.slowPercent)").monospacedDigit() }
            }
            Stepper(value: $prefs.tierLadder.cutPercent, in: prefs.tierLadder.slowPercent...300) {
                LabeledContent("Kes") { Text("%\(prefs.tierLadder.cutPercent)").monospacedDigit() }
            }
            RateField("Yavaşlatma hızı ↓", bytesPerSec: $prefs.tierLadder.slowDownBytesPerSec)
            RateField("Yavaşlatma hızı ↑", bytesPerSec: $prefs.tierLadder.slowUpBytesPerSec)
            Picker("Geçerli olduğu ağ", selection: $prefs.tierLadder.appliesTo) {
                Text(RuleText.scope(.mobileOnly)).tag(NetworkScope.mobileOnly)
                Text(RuleText.scope(.allNetworks)).tag(NetworkScope.allNetworks)
            }
            .pickerStyle(.segmented)
            Stepper(value: $prefs.tierLadder.cutTopCount, in: 0...50) {
                LabeledContent("Kesilecek uygulama sayısı") {
                    Text(prefs.tierLadder.cutTopCount == 0 ? "Hepsi" : "En çok \(prefs.tierLadder.cutTopCount)").monospacedDigit()
                }
            }
            Divider()
            Text("Korunan uygulamalar").font(.subheadline.weight(.medium))
            Text("Yavaşlatma ve kesmeden muaf tutulur. Sistem yolları, Adalmon ve SpoofDPI zaten her zaman korunur.")
                .font(.caption)
                .foregroundStyle(.secondary)
            AppKeyListEditor(model: model, apps: $prefs.tierLadder.protectedApps, emptyText: "Korunan uygulama yok.")
            TierLadderStatusLine(status: model.rules.ladderStatus)
        }
    }
}
