import SwiftUI

struct GeneralSettingsTab: View {
    @Bindable var prefs: Preferences
    let alerts: AlertCenter
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Genel") {
                Picker("Menü çubuğu güncelleme", selection: $prefs.updateInterval) {
                    Text("1 sn").tag(1)
                    Text("2 sn (önerilen)").tag(2)
                    Text("3 sn").tag(3)
                    Text("5 sn").tag(5)
                }
                Text("Panel açıkken her zaman saniyede bir güncellenir. Daha seyrek güncelleme daha az pil harcar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Girişte başlat", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in prefs.launchAtLogin = v }
                Toggle("Dock'ta göster (ana pencere)", isOn: $prefs.showInDock)
                Text("Açıkken Adalmon Dock'ta görünür ve ana pencereyi açar. Kapalıyken yalnızca menü çubuğunda çalışır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            NotificationDeliverySection(prefs: prefs, alerts: alerts)
            LicensesSection()
        }
        .formStyle(.grouped)
        .task { launchAtLogin = prefs.launchAtLogin }
    }
}

/// Ayarlar › Genel › Bildirimler (NOTIF-01): limit, mobil veri, kural ve filtre uyarılarının nasıl geleceği.
private struct NotificationDeliverySection: View {
    @Bindable var prefs: Preferences
    let alerts: AlertCenter

    var body: some View {
        Section("Bildirimler") {
            Picker("Uyarılar nasıl gelsin", selection: $prefs.alertDelivery) {
                ForEach(AlertDelivery.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: prefs.alertDelivery) { _, new in
                Task { await alerts.deliveryChanged(to: new) }
            }
            Text("Uygulama içi uyarı, ekranın üstünde birkaç saniye görünen bir balondur. Sistem bildirimi macOS Bildirim Merkezi'ne düşer; izin yalnızca bu seçenek seçilince istenir. Pil uyarılarının kendi ayarları \"Pil uyarıları\" bölümündedir.")
                .font(.caption).foregroundStyle(.secondary)
            if prefs.alertDelivery.wantsSystem && alerts.permission == .denied {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sistem bildirimi izni kapalı; uyarılar uygulama içinde gösteriliyor.")
                        .font(.caption).foregroundStyle(.orange)
                    Spacer(minLength: 8)
                    Button("Sistem Ayarları'nı aç") { UNSystemNotifier.openSystemSettings() }
                        .controlSize(.small)
                }
            }
        }
        .task { await alerts.refreshPermission() }
    }
}
