import SwiftUI

/// Deneysel: geçerli duvar kâğıdı videosunu Apple'ın Aerial listesine tek kayıt olarak ekler (kilit ekranı / Sistem Ayarları).
/// Anahtar açıkken video değişince kayıt kendiliğinden yenilenir; kapatınca geri alınır. Ayrıntılar bilgi balonundadır.
struct WallpaperLockScreenSection: View {
    @Bindable var service: WallpaperService
    @State private var confirmEnable = false
    @State private var showInfo = false

    private var aerial: WallpaperService.Aerial { service.aerial }
    private var current: WallpaperItem? { AerialAutoSync.currentItem(items: service.items, defaultID: service.settings.defaultItemID) }

    private var showBinding: Binding<Bool> {
        Binding(get: { service.settings.showInSystem },
                set: { on in
                    if on && !service.settings.experimentalAerialAcknowledged { confirmEnable = true } else { service.setShowInSystem(on) }
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Toggle("Kilit ekranında ve Sistem Ayarları'nda da göster (deneysel)", isOn: showBinding)
                    .disabled(!service.settings.showInSystem && (!aerial.compatibility.canInstall || current == nil))
                Button("Ayrıntılar", systemImage: "info.circle") { showInfo = true }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                    .popover(isPresented: $showInfo, arrowEdge: .bottom) { info }
                Spacer(minLength: 0)
            }
            if let line = statusLine {
                Label(line.text, systemImage: line.symbol)
                    .font(.caption).foregroundStyle(line.color)
            }
        }
        .confirmationDialog("Deneysel özellik açılsın mı?", isPresented: $confirmEnable) {
            Button("Aç") { service.setShowInSystem(true) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Apple'ın sistem dosyalarına tek bir kayıt yazılır. Önce yedek alınır, kapatınca geri alınır. Apple bir güncellemede biçimi değiştirirse çalışmayabilir.")
        }
    }

    // MARK: Durum satırı

    private struct Line {
        var text: String
        var symbol: String
        var color: Color
    }

    private var statusLine: Line? {
        if aerial.checked, !aerial.compatibility.canInstall, let message = aerial.compatibility.message {
            // Kapalıyken yalnızca "neden kullanılamıyor" açıklaması (hata değil); açıkken gerçek sorun.
            return service.settings.showInSystem ? Line(text: message, symbol: "xmark.octagon.fill", color: .red)
                                                 : Line(text: message, symbol: "info.circle", color: .secondary)
        }
        guard service.settings.showInSystem else { return nil }
        if aerial.busy { return Line(text: aerial.message ?? "Hazırlanıyor…", symbol: "hourglass", color: .secondary) }
        if aerial.failed, let message = aerial.message {
            return Line(text: message, symbol: "exclamationmark.triangle.fill", color: .orange)
        }
        if case .warning = aerial.compatibility { return Line(text: "macOS 27'de kilit ekranında oynamayabilir.", symbol: "exclamationmark.triangle.fill", color: .orange) }
        switch aerial.status {
        case .installed: return Line(text: "Eklendi" + (current.map { " · \($0.name)" } ?? ""), symbol: "checkmark.circle.fill", color: .green)
        case .drifted: return Line(text: "Apple listeyi yenilemiş; kayıt yeniden eklenecek.", symbol: "arrow.triangle.2.circlepath", color: .orange)
        case .notInstalled: return nil
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kilit ekranı ve Sistem Ayarları").font(.headline)
            Text("Geçerli duvar kâğıdı videosu Apple'ın Aerial listesine (entries.json) tek bir \"Adalmon\" kaydı olarak eklenir. Duvar kâğıdını değiştirince kayıt kendiliğinden yenilenir.")
            Text("Biçim her macOS sürümünde değişebilir; macOS 27'de kayıt listede görünse de kilit ekranında oynamayabilir. Önce yedek alınır, Apple'ın kayıtlarına dokunulmaz. Anahtarı kapatınca kayıt kaldırılır ve yedek geri yüklenir.")
        }
        .font(.callout)
        .frame(width: 320, alignment: .leading)
        .padding(14)
    }
}
