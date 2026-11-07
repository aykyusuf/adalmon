import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Kütüphane ızgarası: "Ekle…" (NSOpenPanel) ve sürükle-bırak. İndirici yoktur; dosyaları kullanıcı seçer.
struct WallpaperLibraryCard: View {
    @Bindable var service: WallpaperService
    @State private var isTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 12, alignment: .top)]

    var body: some View {
        RulesCard(title: "Kütüphane", systemImage: "photo.stack",
                  subtitle: "Video (mov, mp4, m4v) ve görüntü (png, jpg, heic). Dosyalar yerinde kalır; kopyalanmaz.") {
            HStack {
                Button("Ekle…", systemImage: "plus", action: pickFiles)
                    .buttonStyle(.borderedProminent)
                Text("ya da dosyaları buraya sürükleyin").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if service.items.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(service.items) { item in
                        WallpaperTile(item: item, service: service)
                    }
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                .opacity(isTargeted ? 1 : 0)
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await service.importFiles(urls) }
            return !urls.isEmpty
        } isTargeted: { isTargeted = $0 }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    private var emptyState: some View {
        ContentUnavailableView("Henüz içerik yok", systemImage: "photo.badge.plus",
                               description: Text("Bir video ya da görüntü ekleyin. 1080p HEVC videolar en az enerjiyi kullanır."))
            .frame(maxWidth: .infinity, minHeight: 140)
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.title = "Duvar kâğıdı seç"
        panel.prompt = "Ekle"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = WallpaperKind.allExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await service.importFiles(urls) }
    }
}
