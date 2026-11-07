import AppKit
import SwiftUI

enum BatteryAlertSounds {
    static let names = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
}

/// Ayarlar › Pil uyarıları: düşük / dolu eşikleri, takıldı-çıkarıldı; her biri için gösterim, ses, bildirim ve önizleme.
struct BatteryAlertsSettingsPane: View {
    let model: AppModel
    @State private var newLow = 15
    @State private var newCharged = 90

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Section {
                Toggle("Pil uyarılarını aç", isOn: $prefs.batteryAlerts.enabled)
                Text("Uyarı penceresi ve parlama yalnızca gösterildiği anda oluşturulur; bekleme sırasında pil harcamaz. Aynı eşik için tekrar uyarı, pil eşiğin 3 puan ötesine geçmeden verilmez.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Düşük pil") {
                ForEach($prefs.batteryAlerts.low) { $item in
                    AlertActionRow(title: "%\(item.value) ve altı", action: $item.action, onPreview: {
                        model.battery.preview(BatteryAlertEvent(kind: .low(item.value), level: item.value, minutes: max(3, item.value * 3 / 2), action: item.action))
                    }, onDelete: { prefs.batteryAlerts.low.removeAll { $0.value == item.value } })
                }
                addRow(value: $newLow, label: "Eşik ekle") { prefs.batteryAlerts.addLow(newLow) }
            }
            .disabled(!prefs.batteryAlerts.enabled)

            Section("Şarj seviyesi") {
                ForEach($prefs.batteryAlerts.charged) { $item in
                    AlertActionRow(title: item.value >= 100 ? "Tam doldu (%100)" : "%\(item.value)'e ulaşınca", action: $item.action, onPreview: {
                        model.battery.preview(BatteryAlertEvent(kind: .charged(item.value), level: item.value, minutes: nil, action: item.action))
                    }, onDelete: { prefs.batteryAlerts.charged.removeAll { $0.value == item.value } })
                }
                addRow(value: $newCharged, label: "Eşik ekle") { prefs.batteryAlerts.addCharged(newCharged) }
            }
            .disabled(!prefs.batteryAlerts.enabled)

            Section("Şarj aleti") {
                AlertActionRow(title: "Takılınca", action: $prefs.batteryAlerts.pluggedIn, onPreview: {
                    model.battery.preview(BatteryAlertEvent(kind: .pluggedIn, level: 64, minutes: 40, action: prefs.batteryAlerts.pluggedIn))
                }, onDelete: nil)
                AlertActionRow(title: "Çıkarılınca", action: $prefs.batteryAlerts.unplugged, onPreview: {
                    model.battery.preview(BatteryAlertEvent(kind: .unplugged, level: 100, minutes: 612, action: prefs.batteryAlerts.unplugged))
                }, onDelete: nil)
            }
            .disabled(!prefs.batteryAlerts.enabled)
        }
        .formStyle(.grouped)
    }

    private func addRow(value: Binding<Int>, label: String, add: @escaping () -> Void) -> some View {
        HStack {
            Stepper(value: value, in: BatteryAlertConfig.allowedRange) {
                LabeledContent(label, value: "%\(value.wrappedValue)")
            }
            Button("Ekle", action: add)
        }
    }
}

struct AlertActionRow: View {
    let title: String
    @Binding var action: BatteryAlertAction
    let onPreview: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $action.enabled) { Text(title).font(.body.weight(.medium)) }
                Spacer()
                Button("Önizle", systemImage: "play.fill", action: onPreview)
                    .labelStyle(.titleAndIcon).controlSize(.small)
                if let onDelete {
                    Button("Sil", systemImage: "trash", role: .destructive, action: onDelete)
                        .labelStyle(.iconOnly).controlSize(.small)
                }
            }
            if action.enabled {
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Text("Gösterim").foregroundStyle(.secondary)
                        Picker("Gösterim", selection: $action.presentation) {
                            ForEach(BatteryAlertPresentation.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    HStack(spacing: 6) {
                        Text("Ses").foregroundStyle(.secondary)
                        Picker("Ses", selection: $action.sound) {
                            Text("Sessiz").tag(String?.none)
                            Divider()
                            ForEach(BatteryAlertSounds.names, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                        .labelsHidden().fixedSize()
                        .onChange(of: action.sound) { _, new in
                            if let new { NSSound(named: NSSound.Name(new))?.play() }
                        }
                    }
                    Toggle("Bildirim", isOn: $action.notification).toggleStyle(.checkbox)
                    Spacer(minLength: 0)
                }
                .controlSize(.small)
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 2)
    }
}
