import AppKit
import Foundation
import Observation

/// Ekran koruyucu özelliğinin sahibi: ayarlar, kurulum durumu, video hazırlama. UI bunu okur.
/// Hiçbir zamanlayıcı ya da gözlemci yoktur; durum yalnızca sayfa açılınca ve eylemlerden sonra tazelenir.
@MainActor @Observable
final class SaverService {
    static let shared = SaverService()

    var settings: SaverSettings {
        didSet {
            guard settings != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(settings), forKey: Self.settingsKey)
            if settings.shuffle != oldValue.shuffle || settings.hostExitOnStop != oldValue.hostExitOnStop {
                try? store.rewritePlaylistOptions(shuffle: settings.shuffle, hostExitOnStop: settings.hostExitOnStop)
                playlist = store.currentPlaylist()
            }
        }
    }
    private(set) var status: SaverInstaller.Status = .notInstalled
    private(set) var playlist: SaverPlaylist?
    private(set) var plan: SaverContentStore.Plan?
    private(set) var storedBytes: Int64 = 0
    private(set) var progress: Double?
    private(set) var selection: [SaverContentStore.Source] = []
    var message: String?

    @ObservationIgnored let installer: SaverInstaller
    @ObservationIgnored let store: SaverContentStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    private static let settingsKey = "saver.settings"

    var isBusy: Bool { task != nil }
    var isInstalled: Bool {
        switch status {
        case .installed, .updateNeeded: true
        default: false
        }
    }
    var contentIsStale: Bool { SaverSelection.isStale(playlist: playlist, selection: selection) }

    init(installer: SaverInstaller? = nil, store: SaverContentStore? = nil, defaults: UserDefaults = .standard) {
        // Testlerde gerçek ~/Library/Screen Savers ve /Users/Shared'a hiç dokunulmaz.
        let tmp = FileManager.default.temporaryDirectory.appending(path: "adalmon-saver-tests-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
        self.installer = installer ?? (AppEnvironment.isRunningTests ? SaverInstaller(embeddedURL: nil, installDirectory: tmp.appending(path: "ScreenSavers")) : SaverInstaller())
        self.store = store ?? (AppEnvironment.isRunningTests ? SaverContentStore(directory: tmp.appending(path: "Saver")) : SaverContentStore())
        self.defaults = defaults
        settings = defaults.data(forKey: Self.settingsKey).flatMap { try? JSONDecoder().decode(SaverSettings.self, from: $0) } ?? SaverSettings()
    }

    // MARK: Durum

    /// Sayfa açılınca / seçim değişince. Dosya G/Ç (özet, klasör boyutu) arka planda.
    func refresh(wallpaper: WallpaperService) async {
        let chosen = SaverSelection.resolve(settings: settings, wallpaper: wallpaper.settings, items: wallpaper.items)
        let sources = SaverSelection.sources(from: chosen)
        let installer = installer, store = store
        let result = await Task.detached { (installer.status(), store.currentPlaylist(), store.plan(sources), store.diskUsage()) }.value
        selection = sources
        status = result.0
        playlist = result.1
        plan = result.2
        storedBytes = result.3
    }

    // MARK: Eylemler

    /// Videoları hazırlar (klon/kopya) ve paketi kurar/günceller. Ardından Sistem Ayarları açılır.
    func install(wallpaper: WallpaperService) {
        guard task == nil else { return }
        guard !selection.isEmpty else { message = "Önce en az bir video seçin (kütüphanede video olmalı)."; return }
        if let plan, !plan.fits {
            message = "Disk alanı yetersiz: \(plan.bytesToWrite.formatted(.byteCount(style: .file))) gerekiyor, boş alan \(plan.freeBytes.formatted(.byteCount(style: .file))). Aynı birimdeki videolar klonlandığı için ek yer gerekmez; harici diskteki videoları taşıyın ya da yer açın."
            return
        }
        run(wallpaper: wallpaper, openSettingsAfter: true) { [self] in
            try await copyContent()
            try installer.install()
        }
    }

    /// Yalnızca videoları/oynatma listesini günceller (paket zaten kurulu).
    func updateContent(wallpaper: WallpaperService) {
        guard task == nil else { return }
        guard !selection.isEmpty else { message = "Seçili video yok."; return }
        if let plan, !plan.fits { message = "Disk alanı yetersiz (\(plan.bytesToWrite.formatted(.byteCount(style: .file))) gerekiyor)."; return }
        run(wallpaper: wallpaper, openSettingsAfter: false) { [self] in try await copyContent() }
    }

    func uninstall(wallpaper: WallpaperService) {
        guard task == nil else { return }
        do {
            let removed = try installer.uninstall()
            message = removed ? "Ekran koruyucu kaldırıldı. Kopyalanan videolar yerinde; yer açmak için \"Kopyaları sil\"." : "Kurulu bir ekran koruyucu yok."
        } catch {
            message = error.localizedDescription
        }
        Task { await refresh(wallpaper: wallpaper) }
    }

    func clearContent(wallpaper: WallpaperService) {
        guard task == nil else { return }
        do { try store.clear(); message = "Kopyalanan videolar silindi (özgün dosyalarınıza dokunulmadı)." }
        catch { message = error.localizedDescription }
        Task { await refresh(wallpaper: wallpaper) }
    }

    func cancel() { task?.cancel() }

    func openSystemSettings() {
        guard !AppEnvironment.isRunningTests, let url = URL(string: SaverPaths.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: İç

    private func copyContent() async throws {
        let options = SaverContentStore.SyncOptions(shuffle: settings.shuffle, hostExitOnStop: settings.hostExitOnStop,
                                                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
        let sources = selection
        _ = try await store.sync(sources, options: options, makePoster: { source in
            await WallpaperMedia.frameImage(source.url, kind: .video, maxPixel: 960).flatMap { WallpaperMedia.jpegData($0) }
        }, progress: { [weak self] p in Task { @MainActor [weak self] in self?.progress = p } })
    }

    private func run(wallpaper: WallpaperService, openSettingsAfter: Bool, _ work: @escaping @MainActor () async throws -> Void) {
        progress = 0
        message = nil
        task = Task { [weak self] in
            do {
                try await work()
                guard let self else { return }
                message = openSettingsAfter ? "Hazır. Sistem Ayarları'nda \"Adalmon Video\"yu seçin." : "Videolar güncellendi."
                if openSettingsAfter { openSystemSettings() }
            } catch is CancellationError {
                self?.message = "Vazgeçildi."
            } catch {
                self?.message = error.localizedDescription
            }
            guard let self else { return }
            progress = nil
            task = nil
            await refresh(wallpaper: wallpaper)
        }
    }
}
