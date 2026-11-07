import SwiftUI

/// "Gelişmiş": nadir kullanılan eylemler ve teknik notlar (kaldır, kopyaları sil, süreç kapatma, killall notu).
struct WallpaperSaverAdvanced: View {
    @Bindable var wallpaper: WallpaperService
    @Bindable var saver: SaverService
    @Binding var isExpanded: Bool
    @State private var confirmClear = false
    @State private var confirmRestart = false

    var body: some View {
        DisclosureGroup("Gelişmiş", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                actions
                Toggle("Bitince ekran koruyucu sürecini kapat (önerilen)", isOn: $saver.settings.hostExitOnStop)
                    .toggleStyle(.checkbox)
                notes
            }
            .padding(.top, 8)
        }
        .confirmationDialog("Kopyalanan videolar silinsin mi?", isPresented: $confirmClear) {
            Button("Kopyaları sil", role: .destructive) { saver.clearContent(wallpaper: wallpaper) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Yalnızca ekran koruyucunun kopyaları silinir; özgün videolarınıza dokunulmaz. Ekran koruyucu etkinse bir sonraki değişiklikte yeniden hazırlanır.")
        }
        .confirmationDialog("Duvar kâğıdı hizmeti yeniden başlatılsın mı?", isPresented: $confirmRestart) {
            Button("Yeniden başlat") { wallpaper.restartWallpaperAgent() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("macOS hizmeti yeniden başlatır; masaüstü bir an yenilenebilir. Yeni kayıt Sistem Ayarları'nda görünmezse gerekir.")
        }
    }

    private var actions: some View {
        HStack {
            Button("Ayarları aç", systemImage: "gearshape") { saver.openSystemSettings() }
            Button("Kaldır", systemImage: "trash") { saver.uninstall(wallpaper: wallpaper) }
                .disabled(saver.isBusy || !saver.isInstalled)
            if saver.storedBytes > 0 {
                Button("Kopyaları sil (\(saver.storedBytes.formatted(.byteCount(style: .file))))", systemImage: "externaldrive.badge.minus") { confirmClear = true }
                    .disabled(saver.isBusy)
            }
            if wallpaper.settings.showInSystem {
                Button("Sistem listesi hizmetini yeniden başlat…", systemImage: "arrow.clockwise") { confirmRestart = true }
                    .disabled(wallpaper.aerial.busy)
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("macOS bazen ekran koruyucu sürecini (legacyScreenSaver) kapatmayıp bellek ve işlemci kullanır; bu seçenek süreci bitişte sonlandırır. Sorun yaşarsanız kapatın.")
            Text("Ekran koruyucu güncellenince Adalmon eski süreci kendiliğinden kapatır (killall legacyScreenSaver). Eski sürüm yine açılırsa oturumu kapatıp açın.")
            Text("Videolar /Users/Shared/Adalmon/Saver içine kopyalanır; aynı diskte klonlandığı için ek yer kaplamaz. Ekran koruyucu yalnızca Mac boştayken çalışır, pil kuralı uygulanmaz; 4K çözme enerji kullanır, pilde 1080p \"Pil dostu\" kopya önerilir.")
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}
