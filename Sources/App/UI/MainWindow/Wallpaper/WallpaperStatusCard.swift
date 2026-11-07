import SwiftUI

/// Canlı durum satırı + elle karar (otomatik / duraklat / yine de oynat).
struct WallpaperStatusCard: View {
    @Bindable var service: WallpaperService

    var body: some View {
        let summary = service.controller.summary
        RulesCard(title: "Durum", systemImage: "waveform") {
            HStack(spacing: 10) {
                Image(systemName: summary.symbol)
                    .font(.title2)
                    .foregroundStyle(summary.isPlaying ? Color.green : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.text).font(.headline)
                    if service.settings.enabled, case .paused(_, let detail) = summary {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    } else if !service.settings.enabled {
                        Text("Kapalıyken pencere, zamanlayıcı ya da gözlemci yoktur; pil kullanımı sıfırdır.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
            }
            .accessibilityElement(children: .combine)
            if service.settings.enabled {
                Picker("Elle karar", selection: $service.userOverride) {
                    Text("Otomatik").tag(WallpaperUserOverride.auto)
                    Text("Duraklat").tag(WallpaperUserOverride.forcePause)
                    Text("Yine de oynat").tag(WallpaperUserOverride.forcePlay)
                }
                .pickerStyle(.segmented)
                .help("\"Yine de oynat\": pil ve Düşük Güç kurallarını bu oturum için yok sayar. Kilitli ya da uyuyan ekranda yine de durur.")
                if let message = service.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
