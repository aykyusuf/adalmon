import SwiftUI

/// AVAssetImageGenerator ile üretilen (diske önbelleklenen) küçük resim.
struct WallpaperThumbnail: View {
    let item: WallpaperItem
    let service: WallpaperService
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: item.kind == .video ? "film" : "photo")
                    .font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: item.id) { image = await service.thumbnail(for: item) }
    }
}
