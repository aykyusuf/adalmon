import Foundation

/// Ekran koruyucunun kendiliğinden eşitlenmesi ve güncellenmesi için SAF kararlar (G/Ç yok, testte doğrudan denenir).
enum SaverAutoSync {
    /// Duvar kâğıdı seçimi/ayarı değiştikten sonra eşitlemeden önce beklenen süre (art arda tıklamalar tek işe iner).
    static let debounce: Duration = .seconds(2)

    /// Diskteki içerik (videolar + oynatma listesi) istenen duruma uyuyor mu? `false` = eşitleme gerek.
    /// Sıra önemlidir (sırayla oynatmada); döngü ayarı ve karıştırma da listede saklanır.
    static func needsSync(playlist: SaverPlaylist?, selection: [SaverContentStore.Source], shuffle: Bool,
                          hostExitOnStop: Bool, loop: LoopTiming, needsCopy: Bool) -> Bool {
        guard !selection.isEmpty else { return false }   // boş seçimde eldeki listeye dokunulmaz (ör. harici disk takılı değil)
        guard let playlist else { return true }
        if needsCopy { return true }
        if playlist.items.map(\.id) != selection.map(\.id) { return true }
        if playlist.shuffle != shuffle || playlist.hostExitOnStop != hostExitOnStop { return true }
        return playlist.timing != loop.sanitized
    }

    enum UpdateDecision: Equatable, Sendable {
        case none
        /// Kurulu paket bizimki ama uygulamadakinden farklı: sessizce yenile.
        case updateInstalled
    }

    /// Kurulu paketin kendiliğinden güncellenmesi. Hiçbir zaman ilk kurulumu yapmaz; bize ait olmayan pakete dokunmaz.
    /// `failedAvailable`: aynı sürüm için bir kez hata aldıysak her açılışta yeniden denenmez.
    static func updateDecision(status: SaverInstaller.Status, failedAvailable: SaverInstaller.Fingerprint?) -> UpdateDecision {
        guard case .updateNeeded(_, let available) = status else { return .none }
        return available == failedAvailable ? .none : .updateInstalled
    }

    /// Duvar kâğıdıyla aynı modda karıştırma, duvar kâğıdının liste kipinden gelir; elle seçimde kullanıcının tercihi geçerlidir.
    static func effectiveShuffle(settings: SaverSettings, wallpaper: WallpaperSettings) -> Bool {
        switch settings.source {
        case .picked: settings.shuffle
        case .sameAsWallpaper: wallpaper.playlistMode != .sequence
        }
    }
}
