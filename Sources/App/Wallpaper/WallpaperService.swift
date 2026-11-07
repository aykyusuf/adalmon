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

    @ObservationIgnored let controller: WallpaperController
    @ObservationIgnored let directory: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let installer: AerialInstaller
    @ObservationIgnored private var conversionTasks: [UUID: Task<Void, Never>] = [:]

    private static let settingsKey = "wallpaper.settings"

    init(directory: URL = AppEnvironment.supportDirectory.appending(path: "Wallpapers", directoryHint: .isDirectory),
         defaults: UserDefaults = .standard, controller: WallpaperController = WallpaperController(),
         installer: AerialInstaller? = nil) {
        self.directory = directory
        self.defaults = defaults
        self.controller = controller
        self.installer = installer ?? AerialInstaller(supportDirectory: directory.deletingLastPathComponent())
        settings = defaults.data(forKey: Self.settingsKey).flatMap { try? JSONDecoder().decode(WallpaperSettings.self, from: $0) } ?? WallpaperSettings()
        items = Self.loadLibrary(directory)
    }

    /// Uygulama açılışı: ayarlar açıksa denetleyiciyi kurar (kapalıysa hiçbir şey yapmaz).
    func start() { pushConfig() }

    private func pushConfig() {
        controller.apply(.init(settings: settings, items: items, override: userOverride))
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

    // MARK: Deneysel B: sistem duvar kâğıdı / kilit ekranı

    func refreshAerial() {
        guard !AppEnvironment.isRunningTests || installer.root != AerialInstaller.defaultRoot else { return }
        let installer = installer
        Task {
            let (compat, status) = await Task.detached { (installer.compatibility(), installer.status()) }.value
            aerial.compatibility = compat
            aerial.status = status
        }
    }

    func installToSystem(_ id: UUID) {
        guard let source = item(id), source.kind == .video, !aerial.busy, aerial.compatibility.canInstall else { return }
        aerial.busy = true
        aerial.message = "Hazırlanıyor (HEVC Main10, ses yok)…"
        let installer = installer
        let temp = directory.appending(path: ".aerial-tmp", directoryHint: .isDirectory)
        let sourceURL = source.url, name = source.name
        Task {
            do {
                let video = temp.appending(path: "video.mov"), thumb = temp.appending(path: "thumb.png")
                try await AerialEncoder.encode(source: sourceURL, videoDestination: video, thumbnailDestination: thumb) { [weak self] p in
                    Task { @MainActor [weak self] in self?.aerial.message = "Kodlanıyor… %\(Int(p * 100))" }
                }
                let state = try await Task.detached { try installer.install([.init(name: name, videoFile: video, thumbnailFile: thumb)]) }.value
                try? FileManager.default.removeItem(at: temp)
                aerial.message = "Eklendi (\(state.assetIDs.count) kayıt). Sistem Ayarları > Duvar Kâğıdı > \"Adalmon\" kategorisinden seçin; gerekirse hizmeti yeniden başlatın."
            } catch {
                try? FileManager.default.removeItem(at: temp)
                aerial.message = error.localizedDescription
            }
            aerial.busy = false
            refreshAerial()
        }
    }

    func uninstallFromSystem() {
        guard !aerial.busy else { return }
        aerial.busy = true
        let installer = installer
        Task {
            do {
                let method = try await Task.detached { try installer.uninstall() }.value
                aerial.message = switch method {
                case .restoredBackup: "Geri alındı: yedek birebir geri yüklendi."
                case .removedOurEntries: "Geri alındı: yalnızca Adalmon kayıtları çıkarıldı."
                case .nothingToDo: "Geri alınacak bir şey yok."
                }
            } catch {
                aerial.message = error.localizedDescription
            }
            aerial.busy = false
            refreshAerial()
        }
    }

    /// Yalnızca kullanıcı onayıyla (UI onay iletişim kutusu). Testte / geliştirmede çağrılmaz.
    func restartWallpaperAgent() {
        guard !AppEnvironment.isRunningTests else { return }
        do { try WallpaperAgentRestarter.restart(); aerial.message = "Duvar kâğıdı hizmeti yeniden başlatıldı." }
        catch { aerial.message = error.localizedDescription }
    }
}
