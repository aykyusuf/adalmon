import SwiftUI

/// Ekran başına atama: bağlı ekranların adı / çözünürlüğü; "hepsinde aynı" ya da ekran başına içerik.
struct WallpaperDisplaysCard: View {
    @Bindable var service: WallpaperService

    private var screens: [WallpaperScreenInfo] {
        let live = service.controller.screens
        return live.isEmpty ? ScreenMapping.unique(WallpaperController.liveScreens().map(\.info)) : live
    }

    var body: some View {
        RulesCard(title: "Ekranlar", systemImage: "display.2",
                  subtitle: "Ekran eklenip çıkarıldığında ve çözünürlük değiştiğinde pencereler otomatik güncellenir.") {
            Toggle("Tüm ekranlarda aynı içerik", isOn: $service.settings.sameOnAllScreens)
            ForEach(screens) { screen in
                HStack(spacing: 10) {
                    Image(systemName: screen.isMain ? "display" : "display.and.arrow.down")
                        .foregroundStyle(.secondary).frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(screen.name).font(.callout.weight(.medium))
                        Text("\(screen.resolutionText)\(screen.isMain ? " · ana ekran" : "")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if !service.settings.sameOnAllScreens {
                        Picker("İçerik", selection: assignment(for: screen.key)) {
                            Text("Varsayılan").tag(UUID?.none)
                            ForEach(service.items) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 240)
                        .accessibilityLabel("\(screen.name) için içerik")
                    }
                }
            }
        }
    }

    private func assignment(for key: String) -> Binding<UUID?> {
        Binding(get: { service.settings.perScreen[key] },
                set: { service.settings.perScreen[key] = $0 })
    }
}
