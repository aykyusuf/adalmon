import SwiftUI

/// Çalma listesi (sırayla / karışık + aralık) ve kare hızı sınırı.
struct WallpaperPlaylistCard: View {
    @Bindable var service: WallpaperService

    var body: some View {
        RulesCard(title: "Çalma listesi", systemImage: "shuffle",
                  subtitle: "Kütüphanedeki içerikler belirli aralıkla değişir. Duraklatılmışken sayaç da durur.") {
            Picker("Sıra", selection: $service.settings.playlistMode) {
                ForEach(PlaylistMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if service.settings.playlistMode != .single {
                HStack {
                    Picker("Değişim aralığı", selection: $service.settings.rotationMinutes) {
                        ForEach(WallpaperSettings.rotationChoices, id: \.self) { Text(Self.label($0)).tag($0) }
                    }
                    .frame(maxWidth: 280)
                    Button("Sıradakine geç", systemImage: "forward.end") { service.controller.advanceNow() }
                        .disabled(service.items.count < 2)
                }
            }
            Divider()
            Picker("Kare hızı sınırı", selection: $service.settings.frameRateCap) {
                ForEach(WallpaperFrameRateCap.allCases) { Text($0.title).tag($0) }
            }
            .frame(maxWidth: 320)
            Text("Sınır \"Pil dostu dönüştür\" adımında uygulanır. Yerel dosyalarda oynatma sırasında kare hızı sınırlanamaz (AVPlayerItem'ın tepe bit hızı ve azami çözünürlük ayarları yalnızca HLS'te etkilidir; ek video birleştirmesi ise GPU maliyeti ekler).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    static func label(_ minutes: Int) -> String {
        switch minutes {
        case 1_440: "Günde bir"
        case 60...: "\(minutes / 60) saat"
        default: "\(minutes) dakika"
        }
    }
}
