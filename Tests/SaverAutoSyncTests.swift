import XCTest
@testable import Adalmon

/// Otomatik eşitleme kararları (saf), durum satırı ve `defaults` çıktısı ayrıştırma.
final class SaverAutoSyncTests: XCTestCase {
    private func source(_ name: String, id: UUID = UUID()) -> SaverContentStore.Source {
        .init(id: id, name: name, url: URL(filePath: "/tmp/\(name).mov"), byteSize: 10, width: 128, height: 72, duration: 5)
    }

    private func playlist(_ sources: [SaverContentStore.Source], shuffle: Bool = true, hostExit: Bool = true, loop: LoopTiming = .default) -> SaverPlaylist {
        SaverPlaylist(appVersion: "t", updatedAt: .now, shuffle: shuffle, hostExitOnStop: hostExit, trimStart: loop.trimStart, trimEnd: loop.trimEnd,
                      crossfade: loop.crossfade, items: sources.map { SaverPlaylistItem(id: $0.id, name: $0.name, file: $0.storedName, poster: nil, width: 128, height: 72, duration: 5) })
    }

    private func needs(_ list: SaverPlaylist?, _ selection: [SaverContentStore.Source], shuffle: Bool = true, hostExit: Bool = true,
                       loop: LoopTiming = .default, needsCopy: Bool = false) -> Bool {
        SaverAutoSync.needsSync(playlist: list, selection: selection, shuffle: shuffle, hostExitOnStop: hostExit, loop: loop, needsCopy: needsCopy)
    }

    func testNeedsSyncDecisions() {
        let a = source("a"), b = source("b")
        XCTAssertFalse(needs(nil, []), "boş seçimde dokunulmaz")
        XCTAssertFalse(needs(playlist([a]), []), "boş seçim (ör. harici disk yok) mevcut listeyi silmez")
        XCTAssertTrue(needs(nil, [a]), "liste yok")
        XCTAssertFalse(needs(playlist([a, b]), [a, b]), "aynı")
        XCTAssertTrue(needs(playlist([a, b]), [b, a]), "sıra farklı")
        XCTAssertTrue(needs(playlist([a, b]), [a]), "video çıktı: temizlenmeli")
        XCTAssertTrue(needs(playlist([a]), [a, b]), "video eklendi")
        XCTAssertTrue(needs(playlist([a]), [a], needsCopy: true), "kopya eksik")
        XCTAssertTrue(needs(playlist([a], shuffle: true), [a], shuffle: false))
        XCTAssertTrue(needs(playlist([a], hostExit: true), [a], hostExit: false))
        var loop = LoopTiming.default; loop.trimStart += 1
        XCTAssertTrue(needs(playlist([a]), [a], loop: loop), "oynatma ayarı değişti")
        XCTAssertFalse(needs(playlist([a], loop: loop), [a], loop: loop))
    }

    func testEffectiveShuffleFollowsWallpaperInSameMode() {
        var wallpaper = WallpaperSettings()
        var saver = SaverSettings()
        saver.shuffle = false
        wallpaper.playlistMode = .sequence
        XCTAssertFalse(SaverAutoSync.effectiveShuffle(settings: saver, wallpaper: wallpaper), "sıralı duvar kâğıdı -> sıralı")
        wallpaper.playlistMode = .shuffle
        XCTAssertTrue(SaverAutoSync.effectiveShuffle(settings: saver, wallpaper: wallpaper))
        saver.source = .picked
        XCTAssertFalse(SaverAutoSync.effectiveShuffle(settings: saver, wallpaper: wallpaper), "elle seçimde kullanıcının tercihi")
    }

    func testDefaultSourceIsSameAsWallpaper() {
        XCTAssertEqual(SaverSettings().source, .sameAsWallpaper)
    }

    // MARK: Sürüm farkı -> sessiz güncelleme kararı

    private func fp(_ build: String) -> SaverInstaller.Fingerprint { .init(identifier: "id", version: "0.1.0 (\(build))", executableDigest: "d\(build)") }

    func testUpdateDecision() {
        let old = fp("1"), new = fp("2")
        XCTAssertEqual(SaverAutoSync.updateDecision(status: .updateNeeded(installed: old, available: new), failedAvailable: nil), .updateInstalled)
        XCTAssertEqual(SaverAutoSync.updateDecision(status: .updateNeeded(installed: old, available: new), failedAvailable: new), .none, "aynı sürümde hata aldıysak döngüye girme")
        XCTAssertEqual(SaverAutoSync.updateDecision(status: .updateNeeded(installed: old, available: new), failedAvailable: old), .updateInstalled)
        XCTAssertEqual(SaverAutoSync.updateDecision(status: .installed(new), failedAvailable: nil), .none)
        XCTAssertEqual(SaverAutoSync.updateDecision(status: .notInstalled, failedAvailable: nil), .none, "ilk kurulumu kullanıcı yapar")
        XCTAssertEqual(SaverAutoSync.updateDecision(status: .foreign, failedAvailable: nil), .none, "bize ait olmayana dokunulmaz")
        XCTAssertEqual(SaverAutoSync.updateDecision(status: .unavailable, failedAvailable: nil), .none)
    }

    // MARK: Durum satırı

    func testStatusLine() {
        let installed = SaverInstaller.Status.installed(fp("1"))
        let active = SaverStatusLine.make(status: installed, selectedInSystem: true, videoCount: 3)
        XCTAssertEqual(active.text, "Etkin · Adalmon Video · 3 video")
        XCTAssertEqual(active.tone, .ok)
        XCTAssertFalse(active.offersSettings)

        let notSelected = SaverStatusLine.make(status: installed, selectedInSystem: false, videoCount: 3)
        XCTAssertEqual(notSelected.text, "Kurulu ama seçili değil")
        XCTAssertTrue(notSelected.offersSettings)
        XCTAssertTrue(notSelected.showsPickHint)

        let unknown = SaverStatusLine.make(status: .updateNeeded(installed: fp("1"), available: fp("2")), selectedInSystem: nil, videoCount: 1)
        XCTAssertEqual(unknown.text, "Kurulu · Adalmon Video · 1 video")
        XCTAssertTrue(unknown.offersSettings)

        XCTAssertEqual(SaverStatusLine.make(status: .notInstalled, selectedInSystem: nil, videoCount: 0).text, "Henüz etkin değil")
        XCTAssertEqual(SaverStatusLine.make(status: installed, selectedInSystem: true, videoCount: 0).text, "Etkin · Adalmon Video · video yok")
    }

    func testModuleDictParsing() {
        let ours = """
        {
            moduleName = "Adalmon Video";
            path = "/Users/x/Library/Screen Savers/AdalmonSaver.saver";
            type = 0;
        }
        """
        XCTAssertEqual(SaverSystemSelection.parse(ours), .init(name: "Adalmon Video", path: "/Users/x/Library/Screen Savers/AdalmonSaver.saver"))
        XCTAssertTrue(SaverSystemSelection.isOurs(SaverSystemSelection.parse(ours)))
        let apple = """
        {
            moduleName = Drift;
            path = "/System/Library/ExtensionKit/Extensions/Drift.appex";
            type = 0;
        }
        """
        XCTAssertEqual(SaverSystemSelection.parse(apple)?.name, "Drift")
        XCTAssertFalse(SaverSystemSelection.isOurs(SaverSystemSelection.parse(apple)))
        XCTAssertNil(SaverSystemSelection.parse(""))
        XCTAssertFalse(SaverSystemSelection.isOurs(nil))
    }

    func testSelectionUsesLibraryOrderAndStaleIsOrdered() {
        let a = source("a"), b = source("b")
        XCTAssertFalse(SaverSelection.isStale(playlist: playlist([a, b]), selection: [a, b]))
        XCTAssertTrue(SaverSelection.isStale(playlist: playlist([a, b]), selection: [b, a]))
    }
}
