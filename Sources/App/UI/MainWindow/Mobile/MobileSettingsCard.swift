import SwiftUI

/// Fatura dönemi başlangıç günü ve aylık limit ayarları.
struct MobileSettingsCard: View {
    let model: AppModel
    @Bindable var prefs: Preferences

    init(model: AppModel) {
        self.model = model
        self.prefs = model.prefs
    }

    var body: some View {
        MobileCard("Dönem ve limit", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Dönem başlangıcı") {
                    Picker("Dönem başlangıç günü", selection: $prefs.billingCycleStartDay) {
                        ForEach(1...28, id: \.self) { Text("Her ayın \($0). günü").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                LabeledContent("Aylık limit") {
                    HStack(spacing: 10) {
                        if prefs.monthlyCapGB != nil {
                            Stepper(value: monthlyBinding, in: 1...2000, step: 1) {
                                Text("\(Int(prefs.monthlyCapGB ?? 0)) GB")
                                    .monospacedDigit()
                                    .frame(minWidth: 64, alignment: .trailing)
                            }
                        }
                        Toggle("Aylık limit", isOn: monthlyEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                Text("Günlük limit (\(Format.gigabytes(prefs.dailyCapBytes))) aşağıdaki Günlük limit kartından değiştirilir. Aylık limit açıkken günlük bütçe kalan güne göre dinamik hesaplanır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: prefs.billingCycleStartDay) { model.rulesDidChange() }
        .onChange(of: prefs.monthlyCapGB) { model.rulesDidChange() }
    }

    private var monthlyBinding: Binding<Double> {
        Binding(get: { prefs.monthlyCapGB ?? 20 }, set: { prefs.monthlyCapGB = $0 })
    }

    private var monthlyEnabled: Binding<Bool> {
        Binding(get: { prefs.monthlyCapGB != nil }, set: { prefs.monthlyCapGB = $0 ? (prefs.monthlyCapGB ?? 20) : nil })
    }
}
