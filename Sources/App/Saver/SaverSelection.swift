import Foundation

/// Kütüphaneden ekran koruyucu videolarını seçen saf mantık.
enum SaverSelection {
    /// Yalnızca diskte olan, teknik bilgisi okunmuş videolar uygundur.
    static func eligible(_ items: [WallpaperItem]) -> [WallpaperItem] {
        items.filter { $0.kind == .video && $0.info != nil && $0.fileExists }
    }

    static func resolve(settings: SaverSettings, wallpaper: WallpaperSettings, items: [WallpaperItem]) -> [WallpaperItem] {
        let usable = eligible(items)
        switch settings.source {
        case .picked:
            return settings.pickedIDs.compactMap { id in usable.first { $0.id == id } }
        case .sameAsWallpaper:
            switch wallpaper.playlistMode {
            case .single:
                if let id = wallpaper.defaultItemID, let item = usable.first(where: { $0.id == id }) { return [item] }
                return []
            case .sequence, .shuffle:
                return usable
            }
        }
    }

    static func sources(from items: [WallpaperItem]) -> [SaverContentStore.Source] {
        items.compactMap { item in
            guard let info = item.info else { return nil }
            return SaverContentStore.Source(id: item.id, name: item.name, url: item.url, byteSize: item.byteSize,
                                            width: info.width, height: info.height, duration: info.duration)
        }
    }

    /// Diskteki liste seçimle uyuşuyor mu (sıra ve kimlikler)?
    static func isStale(playlist: SaverPlaylist?, selection: [SaverContentStore.Source]) -> Bool {
        guard let playlist else { return !selection.isEmpty }
        return Set(playlist.items.map(\.id)) != Set(selection.map(\.id))
    }
}
