import SwiftUI

/// Pil › Cihazlar: algılanan cihazlar, cihaz başına uyarı zili, menü çubuğuna sabitleme ve gizleme.
struct DevicesTab: View {
    let service: DeviceBatteryService
    let prefs: Preferences
    let battery: BatteryMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if service.visibleDevices.isEmpty {
                emptyState
            } else {
                ForEach(service.visibleDevices) { device in
                    DeviceCard(device: device, settings: settingsBinding(device.id), isPinned: prefs.menuBar.isPinned(device: device.id),
                               onPin: { prefs.menuBar.setPinned(device: device.id, name: device.name, $0) },
                               onPreview: { battery.preview($0) })
                }
            }
            if !service.hiddenDevices.isEmpty { hiddenSection }
            footer
        }
    }

    private func settingsBinding(_ id: String) -> Binding<DeviceSettings> {
        Binding(get: { prefs.deviceSettings[id] ?? DeviceSettings() }, set: { prefs.deviceSettings[id] = $0 })
    }

    private var hiddenSection: some View {
        DisclosureGroup("Gizlenenler (\(service.hiddenDevices.count))") {
            VStack(spacing: 6) {
                ForEach(service.hiddenDevices) { device in
                    HStack {
                        Image(systemName: device.kind.symbol).frame(width: 24).foregroundStyle(.secondary)
                        Text(device.name)
                        Spacer()
                        Text(device.levelText).monospacedDigit().foregroundStyle(.secondary)
                        Button("Göster", systemImage: "eye") { var s = prefs.deviceSettings[device.id] ?? DeviceSettings(); s.hidden = false; prefs.deviceSettings[device.id] = s }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                    .font(.callout)
                }
            }
            .padding(.top, 6)
        }
        .batteryCard(padding: 14)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Cihaz pillerini izle", isOn: Bindable(prefs).deviceMonitoring)
                .onChange(of: prefs.deviceMonitoring) { service.monitoringChanged() }
            HStack(spacing: 10) {
                Button("Şimdi yenile", systemImage: "arrow.clockwise") { service.refreshNow() }
                    .disabled(!prefs.deviceMonitoring || service.isRefreshing)
                if let t = service.lastUpdated { Text("Son güncelleme \(t.formatted(.dateTime.hour().minute()))").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            Label("AirPods değerleri Bluetooth yayınından okunur ve 10’luk adımlarla gelir (~ yaklaşık). Pil için tarama kısa pencerelerle yapılır: sayfa açıkken dakikada bir, arka planda 5 dakikada bir.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch service.bluetoothState {
        case .unauthorized:
            ContentUnavailableView {
                Label("Bluetooth izni gerekli", systemImage: "lock.shield")
            } description: {
                Text("AirPods, klavye, fare ve iPhone pillerini göstermek için Adalmon'a Bluetooth erişimi ver: Sistem Ayarları › Gizlilik ve Güvenlik › Bluetooth.")
            } actions: {
                Button("Sistem Ayarları'nı aç") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") { NSWorkspace.shared.open(url) }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        case .poweredOff:
            ContentUnavailableView("Bluetooth kapalı", systemImage: "wifi.slash",
                                   description: Text("Bluetooth'u aç; bağlı cihazlar burada görünür."))
                .frame(maxWidth: .infinity, minHeight: 260)
        default:
            ContentUnavailableView {
                Label("Henüz cihaz yok", systemImage: "airpods")
            } description: {
                Text("Bluetooth ile bağlı AirPods, klavye, fare ve iPhone/iPad burada görünür. İlk kullanımda macOS Bluetooth izni ister. AirPods için kutuyu aç ya da kulaklığı tak; Mac'inle eşleşmiş olması gerekir.")
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        }
    }
}
