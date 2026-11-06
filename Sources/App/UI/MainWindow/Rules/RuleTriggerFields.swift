import SwiftUI

/// Tetikleyici: kayan ("Son N dakikada ≥ X") ya da sabit pencere ("H saatlik pencerede ≥ X").
struct RuleTriggerFields: View {
    @Binding var draft: RuleDraft

    var body: some View {
        Picker("Pencere", selection: $draft.triggerKind) {
            ForEach(RuleDraft.TriggerKind.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        if draft.triggerKind == .rolling {
            Stepper(value: $draft.minutes, in: 1...RuleTrigger.maxRollingMinutes, step: 5) {
                LabeledContent("Son") { Text("\(draft.minutes) dakika").monospacedDigit() }
            }
        } else {
            Stepper(value: $draft.hours, in: 1...(RuleTrigger.maxFixedMinutes / 60)) {
                LabeledContent("Pencere") { Text("\(draft.hours) saat").monospacedDigit() }
            }
        }
        LabeledContent("Eşik (≥)") {
            HStack(spacing: 6) {
                TextField("Eşik", value: $draft.amount, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Picker("Birim", selection: $draft.unit) {
                    ForEach(RuleDraft.Unit.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        Text(draft.triggerKind == .rolling
             ? "Eşik aşılınca eylem en az pencere uzunluğu kadar sürer; kullanım eşiğin %80'inin altına inince kalkar."
             : "Pencere ilk kullanımda başlar; süre dolunca sayaç sıfırlanır ve eylem kalkar.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
