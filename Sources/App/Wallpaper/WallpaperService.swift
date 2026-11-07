import AppKit
import Foundation
import Observation

/// Duvar kâğıdı özelliğinin sahibi: ayarlar, kütüphane, dönüştürme, deneysel B. UI bunu okur; denetleyici yalnızca pencereleri yönetir.
@MainActor @Observable
final class WallpaperService {
    static let shared = WallpaperService()

    struct Conversion: Equatable {
        var progress: Double
    }

    struct Aerial: Equatable {
        var compatibility: AerialCompatibility
        var status: AerialStatus
        var busy = false
        var message: String?
        /// Son kayıt denemesi başarısız oldu (`message` nedenini söyler).
        var failed = false
        /// Uyumluluk en az bir kez denetlendi (ilk denetimden önce yanlış hata göstermemek için).
        var checked = false
    }

    var settings: WallpaperSettings {
        didSet {
            guard settings != oldValue else { return }
            Self.store(settings, defaults: defaults)
            pushConfig()
        }
    }
    var userOverride: WallpaperUserOverride = .auto { didSet { if userOverride != oldValue { pushConfig() } } }
    private(set) var items: [WallpaperItem]
    private(set) var conversions: [UUID: Conversion] = [:]
    var message: String?
    private(set) var aerial = Aerial(compatibility: .unsupported("Denetlenmedi"), status: .notInstalled)
    /// En son sisteme kaydettiğimiz video (kalıcı): geçerli videoyla karşılaştırılarak yeniden kayıt gerekip gerekmediği anlaşılır.
    private(set) var aerialRegistration: AerialRegistration?

    @ObservationIgnored let controller: WallpaperController
    @ObservationIgnored let directory: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let installer: AerialInstaller
    @ObservationIgnored private var conversionTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var aerialTask: Task<Void, Never>?
    @ObservationIgnored private var aerialFailed: AerialRegistration?
    @ObservationIgnored private var aerialSource: AerialRegistration?
    @ObservationIgnored private var aerialDirty = false
    @ObservationIgnored let aerialDebounce: Duration

    private static let settingsKey = "wallpaper.settings"
    private static let aerialRegistrationKey = "wallpaper.aerialRegistration"

    init(directory: URL = AppEnvironment.supportDirectory.appending(path: "Wallpapers", directoryHint: .isDirectory),
         defaults: UserDefaults = .standard, controller: WallpaperController = WallpaperController(),
         installer: AerialInstaller? = nil, aerialDebounce: Duration = .seconds(3)) {
        self.aerialDebounce = aerialDebounce
        self.directory = directory
        self.defaults = defaults
        self.controller = controller
        self.installer = installer ?? AerialInstaller(supportDirectory: directory.deletingLastPathComponent())
        settings = defaults.data(forKey: Self.settingsKey).flatMap { try? JSONDecoder().decode(WallpaperSettings.self, from: $0) } ?? WallpaperSettings()
        items = Self.loadLibrary(directory)
        aerialRegistration = defaults.data(forKey: Self.aerialRegistrationKey).flatMap { try? JSONDecoder().decode(AerialRegistration.self, from: $0) }
    }

    /// Uygulama açılışı: ayarlar açıksa denetleyiciyi kurar (kapalıysa hiçbir şey yapmaz).
    func start() { pushConfig() }

    private func pushConfig() {
        controller.apply(.init(settings: settings, items: items, override: userOverride))
        noteAerialSource()
    }

    // MARK: Kütüphane

    private var libraryURL: URL { directory.appending(path: "library.json") }
    private var thumbsURL: URL { directory.appending(path: ".thumbs", directoryHint: .isDirectory) }

    private static func loadLibrary(_ directory: URL) -> [WallpaperItem] {
        guard let data = try? Data(contentsOf: directory.appending(path: "library.json")) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([WallpaperItem].self, from: data)) ?? []
    }

    private func saveLibrary() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? enc.encode(items).write(to: libraryURL, options: .atomic)
        pushConfig()
    }

    private static func store(_ s: WallpaperSettings, defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(s), forKey: settingsKey)
    }

    /// Yalnızca önizleme / testler: bir öğenin teknik bilgisini değiştirir.
    func testOverrideInfo(_ info: WallpaperMediaInfo, forFirst count: Int) {
        for i in items.indices.prefix(count) { items[i].info = info }
        pushConfig()
    }

    func item(_ id: UUID?) -> WallpaperItem? { id.flatMap { id in items.first { $0.id == id } } }

    /// NSOpenPanel / sürükle-bırak girişi. Dosya yerinde referanslanır (kopyalanmaz).
    func importFiles(_ urls: [URL]) async {
        var added = 0, skipped = 0
        for url in urls {
            guard let kind = WallpaperKind(url: url) else { skipped += 1; continue }
            if items.contains(where: { $0.path == url.path }) { continue }
            guard let info = await WallpaperMedia.probe(url, kind: kind) else { skipped += 1; continue }
            let item = WallpaperItem(id: UUID(), name: url.deletingPathExtension().lastPathComponent, path: url.path, kind: kind, addedAt: .now,
                                     byteSize: WallpaperMedia.fileSize(url), info: info)
            items.append(item)
            if settings.defaultItemID == nil { settings.defaultItemID = item.id }
            added += 1
        }
        saveLibrary()
        if skipped > 0 { message = "\(skipped) dosya okunamadı ya da desteklenmiyor (mov, mp4, m4v, png, jpg, heic)." }
        else if added > 0 { message = nil }
    }

    func remove(_ id: UUID) {
        guard let item = item(id) else { return }
        conversionTasks[id]?.cancel()
        items.removeAll { $0.id == id }
        // Yalnızca kendi dizinimizdeki (dönüştürülmüş) kopyaları sileriz; kullanıcının özgün dosyasına dokunulmaz.
        if item.path.hasPrefix(directory.path) { try? FileManager.default.removeItem(atPath: item.path) }
        try? FileManager.default.removeItem(at: thumbsURL.appending(path: "\(id.uuidString).jpg"))
        if settings.defaultItemID == id { settings.defaultItemID = items.first?.id }
        settings.perScreen = settings.perScreen.filter { $0.value != id }
        saveLibrary()
    }

    func thumbnail(for item: WallpaperItem) async -> NSImage? {
        let cache = thumbsURL.appending(path: "\(item.id.uuidString)-v2.jpg") // v2: kare artık sürenin ~%15inden; eski siyah küçük resimler yenilenir
        if let data = try? Data(contentsOf: cache), let image = NSImage(data: data) { return image }
        guard let cg = await WallpaperMedia.frameImage(item.url, kind: item.kind, maxPixel: 640), let data = WallpaperMedia.jpegData(cg) else { return nil }
        try? FileManager.default.createDirectory(at: thumbsURL, withIntermediateDirectories: true)
        try? data.write(to: cache, options: .atomic)
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // MARK: Pil dostu dönüştür

    func convert(_ id: UUID) {
        guard let source = item(id), source.kind == .video, conversions[id] == nil else { return }
        conversions[id] = Conversion(progress: 0)
        let cap = settings.frameRateCap
        let destination = directory.appending(path: "\(UUID().uuidString).mov")
        let sourceName = source.name
        let sourceURL = source.url
        let originalSize = source.byteSize
        conversionTasks[id] = Task { [weak self] in
            do {
                try await WallpaperTranscoder.convert(source: sourceURL, destination: destination, cap: cap) { [weak self] value in
                    Task { @MainActor [weak self] in self?.conversions[id] = Conversion(progress: value) }
                }
                guard let self else { return }
                let info = await WallpaperMedia.probe(destination, kind: .video)
                let new = WallpaperItem(id: UUID(), name: "\(sourceName) (pil dostu)", path: destination.path, kind: .video, addedAt: .now,
                                        byteSize: WallpaperMedia.fileSize(destination), info: info, originalByteSize: originalSize, isOptimized: true)
                self.items.append(new)
                self.conversions[id] = nil
                self.conversionTasks[id] = nil
                self.saveLibrary()
                let grew = new.byteSize >= originalSize
                self.message = "Dönüştürüldü: \(originalSize.formatted(.byteCount(style: .file))) → \(new.byteSize.formatted(.byteCount(style: .file)))" + (grew ? " (boyut küçülmedi; kaynak zaten düşük bit hızlı olabilir)" : "")
            } catch {
                try? FileManager.default.removeItem(at: destination)
                guard let self else { return }
                self.conversions[id] = nil
                self.conversionTasks[id] = nil
                self.message = error.localizedDescription
            }
        }
    }

    func cancelConversion(_ id: UUID) { conversionTasks[id]?.cancel() }

    // MARK: Deneysel: kilit ekranı / Sistem Ayarları (Aerial)
    //
    // Tek ilke: "göster" açıkken sistem listesinde HER ZAMAN tek kaydımız vardır ve o, geçerli duvar kâğıdı videosudur.
    // Video değişince kayıt (bizimki) değiştirilir; Apple'ın kayıtlarına dokunulmaz. Kapatınca kayıt otomatik geri alınır.

    func refreshAerial() {
        guard !AppEnvironment.isRunningTests || installer.root != AerialInstaller.defaultRoot else { return }
        let installer = installer
        Task {
            let (compat, status) = await Task.detached { (installer.compatibility(), installer.status()) }.value
            aerial.compatibility = compat
            aerial.status = status
            aerial.checked = true
            // Eski sürümde elle eklenmiş kayıt varsa anahtar açık görünsün (kayıt yeni ilkeye göre sessizce tazelenir).
            if !settings.showInSystem, settings.experimentalAerialAcknowledged, case .installed = status { settings.showInSystem = true }
            else if settings.showInSystem { scheduleAerialSync() }
        }
    }

    /// Anahtar. Açarken kullanıcı onayı arayüzde alınır; kapatınca kayıt geri alınır.
    func setShowInSystem(_ on: Bool) {
        guard on != settings.showInSystem else { return }
        settings.showInSystem = on
        if on {
            settings.experimentalAerialAcknowledged = true
            aerialFailed = nil
            aerialSource = nil
            noteAerialSource()
        } else {
            aerialTask?.cancel()
            aerialDirty = false
            if !aerial.busy { uninstallFromSystem() }   // sürüyorsa kayıt bitince geri alınır
        }
    }

    /// Geçerli video değişti mi? Değiştiyse (ve anahtar açıksa) kısa bir beklemeyle kaydı yeniler. Ağır iş (kodlama) art arda tetiklenmesin diye 3 sn bekler.
    private func noteAerialSource() {
        guard settings.showInSystem else { return }
        let current = AerialAutoSync.currentItem(items: items, defaultID: settings.defaultItemID).map(AerialAutoSync.registration)
        guard current != aerialSource else { return }
        aerialSource = current
        scheduleAerialSync()
    }

    func scheduleAerialSync() {
        guard !AppEnvironment.isRunningTests || installer.root != AerialInstaller.defaultRoot else { return }
        if aerial.busy { aerialDirty = true; return }   // süren kayıt bitince yeniden bakılır
        aerialTask?.cancel()
        let delay = aerialDebounce
        aerialTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await syncAerial()
        }
    }

    private func syncAerial() async {
        guard settings.showInSystem, !aerial.busy else { return }
        let installer = installer
        let (compat, status) = await Task.detached { (installer.compatibility(), installer.status()) }.value
        aerial.compatibility = compat
        aerial.status = status
        aerial.checked = true
        guard !Task.isCancelled else { return }
        let item = AerialAutoSync.currentItem(items: items, defaultID: settings.defaultItemID)
        let action = AerialAutoSync.action(enabled: true, canInstall: compat.canInstall, status: status, current: item.map(AerialAutoSync.registration),
                                           registered: aerialRegistration, failed: aerialFailed)
        guard case .register(let registration) = action, let item else { return }
        await registerInSystem(item, registration: registration)
    }

    /// Videoyu HEVC Main10 (sessiz) kodlar ve tek kaydımız olarak sisteme yazar (öncekinin yerine).
    private func registerInSystem(_ source: WallpaperItem, registration: AerialRegistration) async {
        aerial.busy = true
        aerial.message = "Hazırlanıyor…"
        let installer = installer
        let temp = directory.appending(path: ".aerial-tmp", directoryHint: .isDirectory)
        let sourceURL = source.url, name = source.name
        do {
            let video = temp.appending(path: "video.mov"), thumb = temp.appending(path: "thumb.png")
            try await AerialEncoder.encode(source: sourceURL, videoDestination: video, thumbnailDestination: thumb) { [weak self] p in
                Task { @MainActor [weak self] in self?.aerial.message = "Hazırlanıyor… %\(Int(p * 100))" }
            }
            try await Task.detached { try installer.install([.init(name: name, videoFile: video, thumbnailFile: thumb)]) }.value
            try? FileManager.default.removeItem(at: temp)
            setRegistration(registration)
            aerialFailed = nil
            aerial.failed = false
            aerial.message = "Eklendi: \(name)"
        } catch {
            try? FileManager.default.removeItem(at: temp)
            aerialFailed = registration
            aerial.failed = true
            aerial.message = error.localizedDescription
        }
        aerial.busy = false
        if !settings.showInSystem {
            await performUninstall()   // hazırlanırken anahtar kapatıldı
        } else {
            await refreshAerialState()
            if aerialDirty { aerialDirty = false; scheduleAerialSync() }
        }
    }

    func uninstallFromSystem() {
        guard !aerial.busy else { return }
        Task { await performUninstall() }
    }

    private func performUninstall() async {
        aerial.busy = true
        let installer = installer
        do {
            let method = try await Task.detached { try installer.uninstall() }.value
            aerial.message = switch method {
            case .restoredBackup: "Geri alındı."
            case .removedOurEntries: "Geri alındı: yalnızca Adalmon kaydı çıkarıldı."
            case .nothingToDo: nil
            }
        } catch {
            aerial.message = error.localizedDescription
        }
        setRegistration(nil)
        aerial.busy = false
        await refreshAerialState()
    }

    private func refreshAerialState() async {
        guard !AppEnvironment.isRunningTests || installer.root != AerialInstaller.defaultRoot else { return }
        let installer = installer
        let (compat, status) = await Task.detached { (installer.compatibility(), installer.status()) }.value
        aerial.compatibility = compat
        aerial.status = status
        aerial.checked = true
    }

    private func setRegistration(_ value: AerialRegistration?) {
        aerialRegistration = value
        defaults.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.aerialRegistrationKey)
    }

    /// Yalnızca kullanıcı onayıyla (UI onay iletişim kutusu). Testte / geliştirmede çağrılmaz.
    func restartWallpaperAgent() {
        guard !AppEnvironment.isRunningTests else { return }
        do { try WallpaperAgentRestarter.restart(); aerial.message = "Duvar kâğıdı hizmeti yeniden başlatıldı." }
        catch { aerial.message = error.localizedDescription }
    }
}
