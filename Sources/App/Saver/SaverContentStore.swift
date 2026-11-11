import Foundation

/// Ekran koruyucunun okuyacağı klasörü (videolar + posterler + `playlist.json`) yönetir.
/// Dizin enjekte edilir; testler geçici dizinde çalışır.
struct SaverContentStore: Sendable {
    /// Kütüphaneden seçilen bir video (saf veri).
    struct Source: Equatable, Sendable, Identifiable {
        var id: UUID
        var name: String
        var url: URL
        var byteSize: Int64
        var width: Int
        var height: Int
        var duration: Double

        var fileExtension: String { url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased() }
        var storedName: String { "\(id.uuidString).\(fileExtension)" }
        var posterName: String { "\(id.uuidString).jpg" }
    }

    /// Kopyalamadan önce gösterilen özet: ne kadar yazılacak, sığar mı.
    struct Plan: Equatable, Sendable {
        var totalBytes: Int64
        var alreadyPresentBytes: Int64
        /// Gerçekte yazılacak bayt (klon beklenen dosyalar 0 sayılır).
        var bytesToWrite: Int64
        var cloneExpected: Bool
        var freeBytes: Int64
        var fits: Bool { bytesToWrite == 0 || bytesToWrite + Self.safetyMargin <= freeBytes }
        static let safetyMargin: Int64 = 2 << 30     // 2 GB: disk neredeyse dolu

        var needsCopy: Bool { totalBytes - alreadyPresentBytes > 0 }
    }

    var directory: URL = SaverPaths.sharedDirectory

    var playlistURL: URL { SaverPaths.playlistURL(in: directory) }

    func currentPlaylist() -> SaverPlaylist? { SaverPlaylist.load(from: directory) }

    /// Klasördeki toplam bayt (gerçek boyut: klonlar paylaşılan blokları da sayar, bu yüzden "görünür" boyuttur).
    func diskUsage() -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey]
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e { total += Int64((try? url.resourceValues(forKeys: Set(keys)).fileSize) ?? 0) }
        return total
    }

    // MARK: Plan

    func plan(_ sources: [Source]) -> Plan {
        let fm = FileManager.default
        var present: Int64 = 0, toWrite: Int64 = 0, total: Int64 = 0
        var clone = true
        let dirVolume = Self.volumeID(ofNearestExisting: directory)
        for s in sources {
            total += s.byteSize
            let dest = directory.appending(path: s.storedName)
            if fm.fileExists(atPath: dest.path), WallpaperMedia.fileSize(dest) == s.byteSize { present += s.byteSize; continue }
            let sameVolume = dirVolume != nil && Self.volumeID(ofNearestExisting: s.url) == dirVolume
            if !sameVolume { toWrite += s.byteSize; clone = false }
        }
        let free = Self.freeBytes(ofNearestExisting: directory)
        return Plan(totalBytes: total, alreadyPresentBytes: present, bytesToWrite: toWrite, cloneExpected: clone, freeBytes: free)
    }

    static func volumeID(ofNearestExisting url: URL) -> String? {
        var current = url
        while !FileManager.default.fileExists(atPath: current.path), current.path != "/" { current = current.deletingLastPathComponent() }
        guard let id = try? current.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else { return nil }
        return String(describing: id)
    }

    static func freeBytes(ofNearestExisting url: URL) -> Int64 {
        var current = url
        while !FileManager.default.fileExists(atPath: current.path), current.path != "/" { current = current.deletingLastPathComponent() }
        return (try? current.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
    }

    // MARK: Eşitleme

    struct SyncOptions: Sendable {
        var shuffle: Bool
        var hostExitOnStop: Bool
        var appVersion: String
        /// Baştan atla / sondan kes / çapraz geçiş (duvar kâğıdı ayarlarıyla aynı).
        var loop: LoopTiming = .default
        var fit: LoopFit = .fill
    }

    /// Seçili videoları klasöre getirir (klon/kopya), poster üretir, listeyi atomik yazar, listede olmayan eski dosyaları siler.
    /// Aynı kimlikli ve aynı boyutlu dosya yeniden kopyalanmaz (tekilleştirme). `progress` 0...1 (tüm dosyalar).
    func sync(_ sources: [Source], options: SyncOptions,
              makePoster: @Sendable (Source) async -> Data? = { _ in nil },
              progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> SaverPlaylist {
        let fm = FileManager.default
        try prepareDirectory()
        let totalBytes = max(1, sources.reduce(Int64(0)) { $0 + $1.byteSize })
        var doneBytes: Int64 = 0
        var items: [SaverPlaylistItem] = []
        // Kırpma başlangıcı değiştiyse posterler (ilk oynayan kare) yeniden üretilir.
        let regeneratePosters = currentPlaylist().map { $0.timing.trimStart != options.loop.sanitized.trimStart } ?? false
        for s in sources {
            try Task.checkCancellation()
            let dest = directory.appending(path: s.storedName)
            let base = doneBytes
            if fm.fileExists(atPath: dest.path), WallpaperMedia.fileSize(dest) == s.byteSize {
                // zaten var
            } else {
                try SaverFileCopier.copy(from: s.url, to: dest) { p in progress(min(1, (Double(base) + p * Double(s.byteSize)) / Double(totalBytes))) }
            }
            doneBytes += s.byteSize
            progress(min(1, Double(doneBytes) / Double(totalBytes)))
            var poster: String?
            let posterURL = directory.appending(path: s.posterName)
            if fm.fileExists(atPath: posterURL.path), !regeneratePosters { poster = s.posterName }
            else if let data = await makePoster(s) { try data.write(to: posterURL, options: .atomic); poster = s.posterName }
            items.append(SaverPlaylistItem(id: s.id, name: s.name, file: s.storedName, poster: poster, width: s.width, height: s.height, duration: s.duration))
        }
        let playlist = SaverPlaylist(appVersion: options.appVersion, updatedAt: .now, shuffle: options.shuffle, hostExitOnStop: options.hostExitOnStop,
                                    trimStart: options.loop.trimStart, trimEnd: options.loop.trimEnd, crossfade: options.loop.crossfade, videoFit: options.fit, items: items)
        try playlist.encoded().write(to: playlistURL, options: .atomic)
        prune(keeping: Set(items.flatMap { [$0.file, $0.poster].compactMap { $0 } } + [SaverPaths.playlistFileName]))
        return playlist
    }

    /// Yalnızca oynatma listesini yeniden yazar (karıştır / süreç kapatma değişince; video kopyalamaz).
    func rewritePlaylistOptions(shuffle: Bool, hostExitOnStop: Bool) throws {
        guard var list = currentPlaylist() else { return }
        guard list.shuffle != shuffle || list.hostExitOnStop != hostExitOnStop else { return }
        list.shuffle = shuffle
        list.hostExitOnStop = hostExitOnStop
        list.updatedAt = .now
        try list.encoded().write(to: playlistURL, options: .atomic)
    }

    /// Yalnızca döngü ayarlarını yeniden yazar (video kopyalamaz). Değer aynıysa dosyaya dokunmaz.
    /// `fit` verilmezse listedeki mevcut sığdırma korunur (sessizce Doldur'a dönmesin).
    func rewritePlaylistLoop(_ loop: LoopTiming, fit requestedFit: LoopFit? = nil) throws {
        guard var list = currentPlaylist() else { return }
        let fit = requestedFit ?? list.videoFit
        let wanted = loop.sanitized
        guard list.timing != wanted || list.videoFit != fit else { return }
        list.timing = wanted
        list.videoFit = fit
        list.updatedAt = .now
        try list.encoded().write(to: playlistURL, options: .atomic)
    }

    /// Mevcut öğelerin posterlerini yeniden üretir (kırpma başlangıcı değişince). Videoları kopyalamaz.
    func refreshPosters(_ sources: [Source], makePoster: @Sendable (Source) async -> Data?) async {
        guard var list = currentPlaylist() else { return }
        var changed = false
        for source in sources {
            guard !Task.isCancelled, let index = list.items.firstIndex(where: { $0.id == source.id }) else { continue }
            guard let data = await makePoster(source) else { continue }
            if (try? data.write(to: directory.appending(path: source.posterName), options: .atomic)) != nil, list.items[index].poster != source.posterName {
                list.items[index].poster = source.posterName
                changed = true
            }
        }
        if changed { try? list.encoded().write(to: playlistURL, options: .atomic) }
    }

    /// Klasörü tamamen siler (kopyalanan videolar dahil). Kullanıcının özgün dosyalarına dokunmaz.
    func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func prepareDirectory() throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: directory.path) else { return }
        // Üst klasör (…/Adalmon) yalnızca kullanıcıya açık; ekran koruyucu aynı kullanıcı olarak çalışır.
        let parent = directory.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) { try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    private func prune(keeping names: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        for name in files where !names.contains(name) && !name.hasPrefix(".") { try? fm.removeItem(at: directory.appending(path: name)) }
    }
}
