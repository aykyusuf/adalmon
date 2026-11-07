import SwiftUI

/// Duvar kâğıdı: canlı video / sabit görüntü masaüstü arka planı. Ana şalter kapalıyken hiçbir pencere ya da zamanlayıcı yoktur.
struct WallpaperPage: View {
    @Bindable var service: WallpaperService
    var saver: SaverService = .shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: MainSection.wallpaper.title) {
                    Toggle("Canlı duvar kâğıdı", isOn: $service.settings.enabled)
                        .toggleStyle(.switch)
                }
                WallpaperStatusCard(service: service)
                WallpaperLibraryCard(service: service)
                WallpaperDisplaysCard(service: service)
                WallpaperPlaylistCard(service: service)
                WallpaperPlaybackCard(service: service)
                WallpaperPauseRulesCard(service: service)
                WallpaperSaverCard(wallpaper: service, saver: saver)
            }
            .padding(24)
        }
        .onAppear { service.refreshAerial() }
    }
}
