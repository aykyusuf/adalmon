import AppKit
import Foundation
import Observation

/// Ekran koruyucu özelliğinin sahibi: ayarlar, kurulum durumu, video hazırlama. UI bunu okur.
///
/// Kullanıcı yalnızca "etkinleştir" der; geri kalanı kendiliğinden olur: duvar kâğıdı seçimi/ayarı değişince videolar ve
/// `playlist.json` ~2 sn sonra arka planda eşitlenir, uygulamayla gelen paket farklıysa kurulu paket sessizce yenilenir.
/// Zamanlayıcı yoktur: iş yalnızca bir değişiklik olunca (tek seferlik bekleme) ya da sayfa/uygulama açılınca yapılır.
@MainActor @Observable
final class SaverService {
    static let shared = SaverService()

    var settings: SaverSettings {
        didSet {
            guard settings != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(settings), forKey: Self.settingsKey)
        }
    }
    private(set) var status: SaverInstaller.Status = .notInstalled
    private(set) var playlist: SaverPlaylist?
    private(set) var plan: SaverContentStore.Plan?
    private(set) var storedBytes: Int64 = 0
    private(set) var progress: Double?
    private(set) var selection: [SaverContentStore.Source] = []
    /// Sistem Ayarları'nda bizim ekran koruyucu seçili mi? `nil` = öğrenilemedi.
    private(set) var selectedInSystem: Bool?
    private(set) var isActivating = false
    var message: String?

    @ObservationIgnored let installer: SaverInstaller
    @ObservationIgnored let store: SaverContentStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let hostKiller: @Sendable () -> Void
    @ObservationIgnored private let selectionProbe: @Sendable () -> Bool?
    @ObservationIgnored private var syncWorker: Task<Void, Never>?
    @ObservationIgnored private var syncGeneration = 0
    @ObservationIgnored private var failedUpdate: SaverInstaller.Fingerprint?
    @ObservationIgnored private var isUpdating = false
    /// Testler için: tamamlanan otomatik eşitleme sayısı.
    @ObservationIgnored private(set) var syncRuns = 0
    private static let settingsKey = "saver.settings"

    var isBusy: Bool { isActivating || progress != nil }
    var isInstalled: Bool {
        switch status {
        case .installed, .updateNeeded: true
        default: false
        }
    }
    var statusLine: SaverStatusLine {
        SaverStatusLine.make(status: status, selectedInSystem: selectedInSystem, videoCount: playlist?.items.count ?? selection.count)
    }

    init(installer: SaverInstaller? = nil, store: SaverContentStore? = nil, defaults: UserDefaults = .standard,
         debounce: Duration = SaverAutoSync.debounce, hostKiller: (@Sendable () -> Void)? = nil, selectionProbe: (@Sendable () -> Bool?)? = nil) {
        // Testlerde gerçek ~/Library/Screen Savers, /Users/Shared, `defaults` ve `killall` hiç kullanılmaz.
        let tmp = FileManager.default.temporaryDirectory.appending(path: "adalmon-saver-tests-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
        self.installer = installer ?? (AppEnvironment.isRunningTests ? SaverInstaller(embeddedURL: nil, installDirectory: tmp.appending(path: "ScreenSavers")) : SaverInstaller())
        self.store = store ?? (AppEnvironment.isRunningTests ? SaverContentStore(directory: tmp.appending(path: "Saver")) : SaverContentStore())
        self.defaults = defaults
        self.debounce = debounce
        self.hostKiller = hostKiller ?? Self.defaultHostKiller()
        self.selectionProbe = selectionProbe ?? Self.defaultSelectionProbe()
        settings = defaults.data(forKey: Self.settingsKey).flatMap { try? JSONDecoder().decode(SaverSettings.self, from: $0) } ?? SaverSettings()
    }

    // MARK: Durum

    /// Sayfa açılınca / seçim değişince. Dosya G/Ç (özet, klasör boyutu, `defaults`) arka planda.
    func refresh(wallpaper: WallpaperService) async {
        let sources = SaverSelection.sources(from: SaverSelection.resolve(settings: settings, wallpaper: wallpaper.settings, items: wallpaper.items))
        let installer = installer, store = store, probe = selectionProbe
        let result = await Task.detached { (installer.status(), store.currentPlaylist(), store.plan(sources), store.diskUsage(), probe()) }.value
        selection = sources
        status = result.0
        playlist = result.1
        plan = result.2
        storedBytes = result.3
        selectedInSystem = result.4
        await updateInstalledPackageIfNeeded()
    }

    /// Uygulama öne gelince (Sistem Ayarları'ndan dönüş): yalnızca "seçili mi" bilgisini tazeler.
    func refreshSelectedState() async {
        let probe = selectionProbe
        selectedInSystem = await Task.detached { probe() }.value
    }

    // MARK: Otomatik eşitleme

    /// Duvar kâğıdı seçimi/oynatma ayarı ya da ekran koruyucu ayarı değişti: kısa bir bekleme sonrası (art arda değişiklikler tek işe iner)
    /// videoları ve oynatma listesini günceller. Ekran koruyucu kurulu değilse hiçbir şey kopyalanmaz.
    /// Önceki bekleyen / süren iş iptal edilir (kopya yarım kalmaz: geçici dosyaya yazılıp taşınır).
    func scheduleAutoSync(wallpaper: WallpaperService) {
        syncWorker?.cancel()
        syncGeneration += 1
        let generation = syncGeneration
        let delay = debounce
        syncWorker = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await autoSync(wallpaper: wallpaper, generation: generation)
        }
    }

    /// Uygulama açılışı: ekran koruyucu kuruluysa (tek seferlik) paketi ve videoları güncel tutar; kurulu değilse hiçbir şey yapmaz.
    func launchCheck(wallpaper: WallpaperService) {
        guard FileManager.default.fileExists(atPath: installer.installedURL.path) else { return }
        scheduleAutoSync(wallpaper: wallpaper)
    }

    /// Bekleyen / süren otomatik işi bitirmesini bekler (yalnızca testler).
    func waitForAutoSync() async { await syncWorker?.value }

    private func autoSync(wallpaper: WallpaperService, generation: Int) async {
        guard !isActivating else { return }
        await refresh(wallpaper: wallpaper)
        guard !Task.isCancelled, generation == syncGeneration, isInstalled else { return }
        let needsSync = SaverAutoSync.needsSync(playlist: playlist, selection: selection, shuffle: effectiveShuffle(wallpaper),
                                                hostExitOnStop: settings.hostExitOnStop, loop: wallpaper.settings.loop.timing, fit: wallpaper.settings.loop.fit,
                                                needsCopy: plan?.needsCopy ?? false)
        guard needsSync else { return }
        if let plan, !plan.fits { message = Self.diskMessage(plan); return }
        progress = 0
        do {
            try await copyContent(wallpaper: wallpaper)
            syncRuns += 1
            message = nil
        } catch is CancellationError {
            // Yeni bir değişiklik geldi; yeni iş zaten sırada.
        } catch {
            message = error.localizedDescription
        }
        guard generation == syncGeneration else { return }
        progress = nil
        await refresh(wallpaper: wallpaper)
    }

    // MARK: Eylemler

    /// Videoları hazırlar, paketi kurar ve Sistem Ayarları'nı açar. (Yalnızca ilk kurulumda kullanıcı tıklar.)
    func activate(wallpaper: WallpaperService) {
        guard !isActivating else { return }
        guard !selection.isEmpty else { message = "Önce kütüphaneye bir video ekleyin."; return }
        if let plan, !plan.fits { message = Self.diskMessage(plan); return }
        syncWorker?.cancel()
        syncGeneration += 1
        isActivating = true
        progress = 0
        message = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await copyContent(wallpaper: wallpaper)
                let installer = installer
                try await Task.detached { try installer.install() }.value
                openSystemSettings()
            } catch {
                message = error.localizedDescription
            }
            progress = nil
            isActivating = false
            await refresh(wallpaper: wallpaper)
        }
    }

    func uninstall(wallpaper: WallpaperService) {
        guard !isActivating else { return }
        syncWorker?.cancel()
        syncGeneration += 1
        progress = nil
        do {
            let removed = try installer.uninstall()
            message = removed ? "Ekran koruyucu kaldırıldı. Videoların kopyaları duruyor; yer açmak için \"Kopyaları sil\"." : "Kurulu bir ekran koruyucu yok."
        } catch {
            message = error.localizedDescription
        }
        Task { await refresh(wallpaper: wallpaper) }
    }

    func clearContent(wallpaper: WallpaperService) {
        guard !isActivating else { return }
        syncWorker?.cancel()
        syncGeneration += 1
        progress = nil
        do { try store.clear(); message = "Kopyalar silindi. Özgün videolarınıza dokunulmadı." }
        catch { message = error.localizedDescription }
        Task { await refresh(wallpaper: wallpaper) }
    }

    func openSystemSettings() {
        guard !AppEnvironment.isRunningTests, let url = URL(string: SaverPaths.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: İç

    private func effectiveShuffle(_ wallpaper: WallpaperService) -> Bool {
        SaverAutoSync.effectiveShuffle(settings: settings, wallpaper: wallpaper.settings)
    }

    private func copyContent(wallpaper: WallpaperService) async throws {
        let loop = wallpaper.settings.loop.timing
        let options = SaverContentStore.SyncOptions(shuffle: effectiveShuffle(wallpaper), hostExitOnStop: settings.hostExitOnStop,
                                                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
                                                    loop: loop, fit: wallpaper.settings.loop.fit)
        let sources = selection
        _ = try await store.sync(sources, options: options, makePoster: { source in
            await WallpaperMedia.frameImage(source.url, kind: .video, maxPixel: 960, loop: loop).flatMap { WallpaperMedia.jpegData($0) }
        }, progress: { [weak self] p in Task { @MainActor [weak self] in self?.progress = p } })
    }

    /// Uygulamayla gelen paket kurulu olandan farklıysa sessizce yeniler ve eski sürümü çalıştıran süreci kapatır.
    private func updateInstalledPackageIfNeeded() async {
        guard !isUpdating, SaverAutoSync.updateDecision(status: status, failedAvailable: failedUpdate) == .updateInstalled,
              case .updateNeeded(_, let available) = status else { return }
        isUpdating = true
        defer { isUpdating = false }
        let installer = installer, kill = hostKiller
        do {
            try await Task.detached { try installer.install(); kill() }.value
            status = await Task.detached { installer.status() }.value
        } catch {
            failedUpdate = available
            message = "Ekran koruyucu güncellenemedi: \(error.localizedDescription)"
        }
    }

    private static func defaultHostKiller() -> @Sendable () -> Void {
        if AppEnvironment.isRunningTests { return {} }
        return killLegacyScreenSaver
    }

    private static func defaultSelectionProbe() -> @Sendable () -> Bool? {
        if AppEnvironment.isRunningTests { return { nil } }
        return { SaverSystemSelection.isOursSelected() }
    }

    private static func diskMessage(_ plan: SaverContentStore.Plan) -> String {
        "Disk alanı yetersiz: \(plan.bytesToWrite.formatted(.byteCount(style: .file))) gerekiyor, boş alan \(plan.freeBytes.formatted(.byteCount(style: .file)))."
    }

    /// `killall legacyScreenSaver`: macOS eski paketi bellekte tutuyorsa yeni sürüm hemen açılsın diye (yalnızca güncellemeden sonra).
    private static let killLegacyScreenSaver: @Sendable () -> Void = {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/killall")
        process.arguments = ["legacyScreenSaver"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}
