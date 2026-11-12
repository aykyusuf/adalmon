import SwiftUI

struct MobileDataSettingsTab: View {
    let model: AppModel
    @Bindable var prefs: Preferences

    init(model: AppModel) {
        self.model = model
        self.prefs = model.prefs
    }

    var body: some View {
        Form {
            Section("Mobil veri") {
                LabeledContent("Günlük limit") {
                    HStack {
                        Slider(value: $prefs.dailyCapGB, in: 0.5...20, step: 0.5)
                        Text("\(prefs.dailyCapGB.formatted(.number.precision(.fractionLength(1)))) GB")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                LabeledContent("Ani kullanım uyarısı") {
                    HStack {
                        Slider(value: $prefs.burstThresholdMB, in: 10...500, step: 10)
                        Text("\(Int(prefs.burstThresholdMB)) MB/dk")
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                Toggle("Bu ağı her zaman mobil veri say", isOn: $prefs.forceMobile)
                Text("iPhone hotspot (Wi-Fi ve USB) otomatik algılanır. Algılanmayan bir modem için bunu aç.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Engellenenler") {
                let entries = BlockedAppEntry.list(mobile: prefs.blockedOnMobile, wifi: prefs.blockedOnWiFi)
                if entries.isEmpty {
                    Text("Yok. Paneldeki ✋ düğmesiyle ya da bildirimden ekleyebilirsin.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack {
                            Image(nsImage: AppCatalog.shared.icon(for: entry.app))
                                .resizable()
                                .frame(width: 16, height: 16)
                                .accessibilityHidden(true)
                            Text(AppCatalog.shared.name(for: entry.app))
                            BlockScopeBadge(scope: entry.scope)
                            Spacer()
                            Button("Kaldır") { model.setBlockScope(entry.app, nil) }
                                .accessibilityLabel("\(AppCatalog.shared.name(for: entry.app)) engelini kaldır")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
