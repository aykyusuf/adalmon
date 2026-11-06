import SwiftUI

struct GeneralSettingsTab: View {
    @Bindable var prefs: Preferences
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
        }
        .formStyle(.grouped)
        .task { launchAtLogin = prefs.launchAtLogin }
    }
}
