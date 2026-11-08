import SwiftUI

/// Duvar kâğıdı: canlı video / sabit görüntü masaüstü arka planı. Ana şalter kapalıyken hiçbir pencere ya da zamanlayıcı yoktur.
struct WallpaperPage: View {
    @Bindable var service: WallpaperService
    var saver: SaverService = .shared
    /// Ofis kaynağı yalnızca ajan özelliği açıkken anlamlıdır; kapalıysa kartta uyarı gösterilir.
    var agentsEnabled = true
    var openAgents: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: MainSection.wallpaper.title) {
                    Toggle("Canlı duvar kâğıdı", isOn: $service.settings.enabled)
                        .toggleStyle(.switch)
                }
                WallpaperStatusCard(service: service)
                WallpaperSourceCard(service: service)
                if service.settings.source == .office {
                    WallpaperOfficeCard(service: service, agentsEnabled: agentsEnabled, openAgents: openAgents)
                }
                // Ofis kaynağında video kartları sönük ve devre dışı (düzen aynı kalır).
                Group {
                    WallpaperLibraryCard(service: service)
                    WallpaperDisplaysCard(service: service)
                    WallpaperPlaylistCard(service: service)
                    WallpaperPlaybackCard(service: service)
                }
                .opacity(service.settings.source == .office ? 0.4 : 1)
                .disabled(service.settings.source == .office)
                WallpaperPauseRulesCard(service: service)
                WallpaperSaverCard(wallpaper: service, saver: saver)
            }
            .padding(24)
        }
        .onAppear { service.refreshAerial() }
    }
}
