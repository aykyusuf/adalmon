import SwiftUI

/// Şarj sınırı + seyir + "Şarjı şimdi tamamla".
struct ChargeLimitCard: View {
    let model: ChargingModel

    @State private var enabledDraft = false
    @State private var limitDraft = 80.0
    @State private var gapDraft = 5
    @State private var synced = false

    private var supported: Bool { model.status?.supportsChargeLimit ?? false }
    private var limit: Int { Int(limitDraft) }
    private var floor: Int { ChargingPreferences.sailingFloor(limit: limit, gap: gapDraft) }
    private var isTopUp: Bool { model.status?.config.isTopUp ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Şarj sınırı", systemImage: "battery.75percent").font(.headline)

            if model.status != nil, !supported {
                Label("""
                Bu Mac'te doğrulanmış bir şarj engelleme anahtarı (CHTE ya da CH0B/CH0C) bulunamadı; şarj sınırı bu macOS sürümünde \
                kullanılamaz. Hiçbir şey yazılmaz.
                """, systemImage: "nosign")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Toggle("Şarjı sınırla", isOn: $enabledDraft)
                .disabled(!supported || model.isBusy)

            HStack {
                Text("Sınır").frame(width: 90, alignment: .leading)
                Slider(value: $limitDraft, in: Double(HelperConstants.limitRange.lowerBound)...Double(HelperConstants.limitRange.upperBound),
                       step: Double(HelperConstants.limitStep)) { editing in
                    if !editing { Task { await model.setLimit(limit) } }
                }
                .accessibilityLabel("Şarj sınırı")
                .accessibilityValue("yüzde \(limit)")
                Text("%\(limit)").monospacedDigit().frame(width: 50, alignment: .trailing)
            }
            .disabled(!supported || model.isBusy)

            Picker("Seyir aralığı", selection: $gapDraft) {
                Text("5 puan").tag(5)
                Text("10 puan").tag(10)
                Text("15 puan").tag(15)
            }
            .pickerStyle(.segmented)
            .disabled(!supported || model.isBusy || limit >= 100)

            Text(limit >= 100
                 ? "%100: sınır yok, şarj normal çalışır."
                 : "Pil %\(limit)'e ulaşınca şarj durur (Mac fişten çalışır); %\(floor)'in altına inince yeniden başlar (Seyir).")
                .font(.callout).foregroundStyle(.secondary)

            Divider()

            HStack {
                if isTopUp {
                    Label("Şarj tamamlanıyor… pil dolunca ya da fiş çekilince sınır geri gelir.", systemImage: "bolt.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("İptal") { Task { await model.cancelTopUp() } }
                } else {
                    Button("Şarjı şimdi tamamla", systemImage: "bolt.badge.checkmark") { Task { await model.startTopUp() } }
                        .disabled(!supported || !enabledDraft || model.isBusy)
                    Spacer()
                }
                if let status = model.status, supported {
                    Text(stateLine(status)).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .batteryCard()
        .onAppear { syncFromModel() }
        .onChange(of: enabledDraft) { _, new in
            guard synced, new != model.limitEnabled else { return }
            Task { await model.setLimitEnabled(new) }
        }
        .onChange(of: gapDraft) { _, new in
            guard synced, new != model.sailingGap else { return }
            Task { await model.setSailingGap(new) }
        }
    }

    private func syncFromModel() {
        enabledDraft = model.limitEnabled
        limitDraft = Double(model.limit)
        gapDraft = model.sailingGap
        synced = true
    }

    private func stateLine(_ status: HelperStatus) -> String {
        let level = status.batteryLevel.map { "Pil %\($0)" } ?? "Pil ?"
        switch status.isInhibitingCharge {
        case true: return "\(level) · şarj durduruldu"
        case false: return "\(level) · şarj serbest"
        case nil: return level
        }
    }
}
