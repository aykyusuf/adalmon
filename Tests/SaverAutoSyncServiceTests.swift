import XCTest
@testable import Adalmon

/// Otomatik eşitleme ve sessiz güncelleme, hizmet düzeyinde: her şey geçici dizinde; gerçek kurulum, `defaults` ve `killall` yok.
@MainActor
final class SaverAutoSyncServiceTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    private var tmp: URL!
    private var embedded: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "saver-auto-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        embedded = tmp.appending(path: "App/AdalmonSaver.saver")
        suite = "adalmon.saver.auto.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmp)
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeBundle(build: String) throws {
        let macOS = embedded.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": SaverPaths.bundleIdentifier, "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": build, "CFBundleExecutable": "AdalmonSaver"]
        (info as NSDictionary).write(to: embedded.appending(path: "Contents/Info.plist"), atomically: true)
        try Data("code-\(build)".utf8).write(to: macOS.appending(path: "AdalmonSaver"))
    }

    private func makeWallpaper(videos: Int) async throws -> WallpaperService {
        let controller = WallpaperController(isHeadless: true, screenProvider: { [] }, occlusionProvider: { _ in [:] })
        let service = WallpaperService(directory: tmp.appending(path: "Wallpapers"), defaults: defaults, controller: controller,
                                       installer: AerialInstaller(root: tmp.appending(path: "no-aerials"), supportDirectory: tmp))
        var files: [URL] = []
        for i in 0..<videos {
            let v = tmp.appending(path: "clip\(i).mov")
            try await TinyMedia.video(at: v, frames: 6, hue: CGFloat(i) * 0.3 + 0.1)
            files.append(v)
        }
        await service.importFiles(files)
        return service
    }

    private func makeSaver(kill: Counter = Counter()) -> SaverService {
        SaverService(installer: SaverInstaller(embeddedURL: embedded, installDirectory: tmp.appending(path: "ScreenSavers")),
                     store: SaverContentStore(directory: tmp.appending(path: "Shared/Saver")), defaults: defaults,
                     debounce: .milliseconds(80), hostKiller: { kill.bump() }, selectionProbe: { true })
    }

    func testRapidChangesCollapseIntoOneSyncAndFollowLatestSelection() async throws {
        try makeBundle(build: "1")
        let wallpaper = try await makeWallpaper(videos: 2)
        let first = wallpaper.items[0], second = wallpaper.items[1]
        wallpaper.settings.defaultItemID = first.id
        let saver = makeSaver()
        try saver.installer.install()
        await saver.refresh(wallpaper: wallpaper)

        saver.scheduleAutoSync(wallpaper: wallpaper)
        await saver.waitForAutoSync()
        XCTAssertEqual(saver.syncRuns, 1, "ilk eşitleme")
        XCTAssertEqual(saver.store.currentPlaylist()?.items.map(\.id), [first.id])

        // Art arda seçim değişikliği: tek eşitleme, son seçim geçerli; çıkan videonun kopyası silinir.
        wallpaper.settings.defaultItemID = second.id
        saver.scheduleAutoSync(wallpaper: wallpaper)
        saver.scheduleAutoSync(wallpaper: wallpaper)
        wallpaper.settings.defaultItemID = first.id
        wallpaper.settings.defaultItemID = second.id
        saver.scheduleAutoSync(wallpaper: wallpaper)
        await saver.waitForAutoSync()
        XCTAssertEqual(saver.syncRuns, 2, "üç tetik tek işe inmeli")
        XCTAssertEqual(saver.store.currentPlaylist()?.items.map(\.id), [second.id])
        let stored = try FileManager.default.contentsOfDirectory(atPath: saver.store.directory.path)
        XCTAssertFalse(stored.contains { $0.hasPrefix(first.id.uuidString) }, "listeden çıkan video silinmeli")

        // Değişiklik yok: iş çıkmaz.
        saver.scheduleAutoSync(wallpaper: wallpaper)
        await saver.waitForAutoSync()
        XCTAssertEqual(saver.syncRuns, 2)
    }

    func testPlaybackModeChangeRewritesPlaylistWithoutButton() async throws {
        try makeBundle(build: "1")
        let wallpaper = try await makeWallpaper(videos: 2)
        let saver = makeSaver()
        try saver.installer.install()
        wallpaper.settings.playlistMode = .single
        saver.scheduleAutoSync(wallpaper: wallpaper); await saver.waitForAutoSync()
        XCTAssertEqual(saver.store.currentPlaylist()?.items.count, 1)
        wallpaper.settings.playlistMode = .sequence
        saver.scheduleAutoSync(wallpaper: wallpaper); await saver.waitForAutoSync()
        let list = try XCTUnwrap(saver.store.currentPlaylist())
        XCTAssertEqual(list.items.count, 2, "çalma listesi kipinde tüm videolar")
        XCTAssertFalse(list.shuffle, "sıralı kip -> karıştırma kapalı")
    }

    func testNothingIsCopiedBeforeActivation() async throws {
        try makeBundle(build: "1")
        let wallpaper = try await makeWallpaper(videos: 1)
        let saver = makeSaver()                         // paket kurulu değil
        saver.scheduleAutoSync(wallpaper: wallpaper); await saver.waitForAutoSync()
        XCTAssertEqual(saver.syncRuns, 0)
        XCTAssertNil(saver.store.currentPlaylist())
        XCTAssertEqual(saver.status, .notInstalled)
    }

    func testVersionMismatchUpdatesSilentlyOnceAndKillsHostOnce() async throws {
        try makeBundle(build: "1")
        let wallpaper = try await makeWallpaper(videos: 1)
        let kill = Counter()
        let saver = makeSaver(kill: kill)
        try saver.installer.install()
        await saver.refresh(wallpaper: wallpaper)
        guard case .installed = saver.status else { return XCTFail("kurulu olmalı: \(saver.status)") }
        XCTAssertEqual(kill.count, 0, "fark yokken süreç kapatılmaz")

        try makeBundle(build: "2")                       // uygulama güncellendi
        await saver.refresh(wallpaper: wallpaper)
        guard case .installed(let fp) = saver.status else { return XCTFail("sessizce güncellenmiş olmalı: \(saver.status)") }
        XCTAssertEqual(fp.version, "0.1.0 (2)")
        XCTAssertEqual(kill.count, 1)
        XCTAssertEqual(try String(contentsOf: saver.installer.installedURL.appending(path: "Contents/MacOS/AdalmonSaver"), encoding: .utf8), "code-2")

        await saver.refresh(wallpaper: wallpaper)
        XCTAssertEqual(kill.count, 1, "ikinci kez güncelleme yok")
    }

    func testNotInstalledIsNeverAutoInstalled() async throws {
        try makeBundle(build: "1")
        let wallpaper = try await makeWallpaper(videos: 1)
        let kill = Counter()
        let saver = makeSaver(kill: kill)
        await saver.refresh(wallpaper: wallpaper)
        XCTAssertEqual(saver.status, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saver.installer.installedURL.path))
        XCTAssertEqual(kill.count, 0)
    }
}
