import SwiftUI

/// Deneysel (Seçenek B): seçilen videoyu Apple'ın Aerial listesine ekler; böylece Sistem Ayarları > Duvar Kâğıdı'nda
/// ve kilit ekranında görünebilir. Apple'ın dahili biçimini kullanır, kırılgandır, kapalı gelir.
struct WallpaperExperimentalCard: View {
    @Bindable var service: WallpaperService
    @State private var confirmEnable = false
    @State private var confirmInstall = false
    @State private var confirmRestart = false
    @State private var selection: UUID?

    private var videos: [WallpaperItem] { service.items.filter { $0.kind == .video && $0.fileExists } }
    private var aerial: WallpaperService.Aerial { service.aerial }

    var body: some View {
        RulesCard(title: "Deneysel", systemImage: "flask") {
            VStack(alignment: .leading, spacing: 12) {
                Label("Sistem duvar kâğıdına / kilit ekranına ekle", systemImage: "lock.display")
                    .font(.callout.weight(.semibold))
                Text("Apple'ın dahili Aerial listesine (entries.json) kayıt ekler. Biçim her macOS sürümünde değişebilir; macOS 27'de kilit ekranı oynatması çalışmayabilir. Önce yedek alınır, yalnızca Adalmon kayıtları eklenip çıkarılır.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = aerial.compatibility.message {
                    Label(message, systemImage: aerial.compatibility.canInstall ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(aerial.compatibility.canInstall ? Color.orange : Color.red)
                }
                if service.settings.experimentalAerialAcknowledged {
                    controls
                } else {
                    Button("Deneysel özelliği aç…") { confirmEnable = true }
                }
            }
        }
        .confirmationDialog("Deneysel özellik açılsın mı?", isPresented: $confirmEnable) {
            Button("Anladım, aç") { service.settings.experimentalAerialAcknowledged = true }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bu özellik Apple'ın sistem dosyalarına yazar. Yedek alınır ve \"Geri al\" ile geri döner; yine de Apple bir güncellemede biçimi değiştirebilir.")
        }
        .confirmationDialog("Sistem listesine eklensin mi?", isPresented: $confirmInstall) {
            Button("Ekle") { if let id = selection ?? videos.first?.id { service.installToSystem(id) } }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Video HEVC Main10 olarak (ses olmadan) yeniden kodlanır ve Aerial klasörüne kopyalanır. Disk alanı kullanır.")
        }
        .confirmationDialog("Duvar kâğıdı hizmeti yeniden başlatılsın mı?", isPresented: $confirmRestart) {
            Button("Yeniden başlat") { service.restartWallpaperAgent() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("WallpaperAgent kapatılır ve macOS yeniden başlatır; masaüstü bir an yenilenebilir. Yeni kayıt Ayarlar'da görünmezse gerekir.")
        }
    }

    @ViewBuilder private var controls: some View {
        if videos.isEmpty {
            Text("Önce kütüphaneye bir video ekleyin.").font(.caption).foregroundStyle(.secondary)
        } else {
            Picker("Video", selection: Binding(get: { selection ?? videos.first?.id }, set: { selection = $0 })) {
                ForEach(videos) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            .frame(maxWidth: 360)
        }
        HStack {
            Button("Sistem listesine ekle…") { confirmInstall = true }
                .disabled(videos.isEmpty || aerial.busy || !aerial.compatibility.canInstall)
            Button("Geri al") { service.uninstallFromSystem() }
                .disabled(aerial.busy || aerial.status == .notInstalled)
            Button("Hizmeti yeniden başlat…") { confirmRestart = true }
                .disabled(aerial.busy || aerial.status == .notInstalled)
            if aerial.busy { ProgressView().controlSize(.small) }
        }
        Text(statusText).font(.caption).foregroundStyle(.secondary)
        if let m = aerial.message { Text(m).font(.caption) }
        Button("Deneysel bölümü kapat") { service.settings.experimentalAerialAcknowledged = false }
            .buttonStyle(.link).font(.caption)
    }

    private var statusText: String {
        switch aerial.status {
        case .notInstalled: "Durum: eklenmemiş"
        case .installed(let n): "Durum: \(n) kayıt eklendi"
        case .drifted: "Durum: Apple listeyi yenilemiş, kayıtlarımız silinmiş; yeniden ekleyin ya da geri alıp temizleyin"
        }
    }
}
