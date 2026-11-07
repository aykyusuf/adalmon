import SwiftUI

/// Cihaz başına düşük pil uyarısı ayarı (zil düğmesi).
struct DeviceAlertPopover: View {
    let name: String
    @Binding var settings: DeviceSettings
    var onPreview: (BatteryAlertEvent) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(name) uyarıları").font(.headline)
            Toggle("Düşük pil uyarısı", isOn: $settings.alertEnabled)
            if settings.alertEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Eşikler").font(.caption).foregroundStyle(.secondary)
                    ForEach(settings.lowThresholds, id: \.self) { value in
                        HStack {
                            Label("%\(value) altına inince", systemImage: "battery.25percent").font(.callout)
                            Spacer()
                            Button("Kaldır", systemImage: "minus.circle") { settings.lowThresholds.removeAll { $0 == value } }
                                .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(settings.lowThresholds.count <= 1)
                        }
                    }
                    Menu("Eşik ekle", systemImage: "plus.circle") {
                        ForEach([50, 40, 30, 25, 20, 15, 10, 5].filter { !settings.lowThresholds.contains($0) }, id: \.self) { value in
                            Button("%\(value)") { settings.addThreshold(value) }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                Picker("Gösterim", selection: $settings.action.presentation) {
                    ForEach(BatteryAlertPresentation.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Ses", isOn: Binding(get: { settings.action.sound != nil }, set: { settings.action.sound = $0 ? "Glass" : nil }))
                Toggle("Bildirim merkezi", isOn: $settings.action.notification)
                Button("Önizle", systemImage: "play.circle") {
                    let level = settings.lowThresholds.max() ?? 20
                    onPreview(BatteryAlertEvent(kind: .low(level), level: level, minutes: nil, action: settings.action, subject: name))
                }
            }
        }
        .padding(14)
        .frame(width: 290, alignment: .leading)
    }
}
