import XCTest
@testable import Adalmon

/// Video hazırlama: klon/kopya, tekilleştirme, silme, plan, seçim. Her şey geçici dizinde; test videoları birkaç KB.
final class SaverContentStoreTests: XCTestCase {
    private var tmp: URL!
    private var store: SaverContentStore!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "saver-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        store = SaverContentStore(directory: tmp.appending(path: "Shared/Adalmon/Saver"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func source(_ name: String, hue: CGFloat = 0.3) async throws -> SaverContentStore.Source {
        let url = tmp.appending(path: "\(name).mov")
        try await TinyMedia.video(at: url, frames: 6, hue: hue)
        return .init(id: UUID(), name: name, url: url, byteSize: WallpaperMedia.fileSize(url), width: 128, height: 72, duration: 0.2)
    }

    private let options = SaverContentStore.SyncOptions(shuffle: true, hostExitOnStop: true, appVersion: "test")

    func testSyncCopiesWritesPlaylistAndIsPrivate() async throws {
        let a = try await source("a"), b = try await source("b", hue: 0.8)
        let list = try await store.sync([a, b], options: options) { _ in Data([0xFF, 0xD8, 0xFF]) }
        XCTAssertEqual(list.items.map(\.name), ["a", "b"])
        let onDisk = try XCTUnwrap(store.currentPlaylist())
        XCTAssertEqual(onDisk.items.map(\.id), [a.id, b.id])
        XCTAssertEqual(onDisk.playable(in: store.directory).count, 2, "kopyalanan dosyalar listeyle eşleşmeli")
        XCTAssertEqual(try Data(contentsOf: store.directory.appending(path: a.storedName)), try Data(contentsOf: a.url))
        // Dizin yalnızca kullanıcıya açık (0700)
        let perms = try FileManager.default.attributesOfItem(atPath: store.directory.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o700)
        XCTAssertGreaterThan(store.diskUsage(), a.byteSize)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.url.path), "özgün dosyaya dokunulmaz")
    }

    func testSecondSyncDedupesAndPrunesRemovedItems() async throws {
        let a = try await source("a"), b = try await source("b", hue: 0.8)
        _ = try await store.sync([a, b], options: options) { _ in Data([1]) }
        let dest = store.directory.appending(path: a.storedName)
        let before = try FileManager.default.attributesOfItem(atPath: dest.path)
        let inodeBefore = before[.systemFileNumber] as? Int
        let plan = store.plan([a, b])
        XCTAssertEqual(plan.alreadyPresentBytes, a.byteSize + b.byteSize)
        XCTAssertFalse(plan.needsCopy)

        _ = try await store.sync([a], options: options) { _ in Data([1]) }
        let after = try FileManager.default.attributesOfItem(atPath: dest.path)
        XCTAssertEqual(after[.systemFileNumber] as? Int, inodeBefore, "aynı dosya yeniden yazılmamalı")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appending(path: b.storedName).path), "listeden çıkan video silinmeli")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appending(path: b.posterName).path))
        XCTAssertEqual(store.currentPlaylist()?.items.count, 1)
    }

    func testPlanSameVolumeNeedsNoExtraSpaceAndSmallDiskWarns() async throws {
        let a = try await source("a")
        var plan = store.plan([a])
        XCTAssertTrue(plan.cloneExpected)
        XCTAssertEqual(plan.bytesToWrite, 0)
        XCTAssertTrue(plan.fits)
        XCTAssertGreaterThan(plan.freeBytes, 0)
        // Gerçek kopya gereken ve boş alandan büyük durum
        plan = .init(totalBytes: 50 << 30, alreadyPresentBytes: 0, bytesToWrite: 50 << 30, cloneExpected: false, freeBytes: 10 << 30)
        XCTAssertFalse(plan.fits)
        plan.freeBytes = 60 << 30
        XCTAssertTrue(plan.fits)
        plan.freeBytes = (50 << 30) + (1 << 30)
        XCTAssertFalse(plan.fits, "2 GB güvenlik payı")
    }

    func testStreamCopyReportsProgressAndLeavesNoPartialFile() throws {
        let src = tmp.appending(path: "big.bin")
        try Data(repeating: 7, count: 300_000).write(to: src)
        let dst = tmp.appending(path: "out/big.bin")
        try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        let seen = LockedBox<[Double]>([])
        let method = try SaverFileCopier.copy(from: src, to: dst, chunkSize: 64_000, allowClone: false) { p in seen.mutate { $0.append(p) } }
        XCTAssertEqual(method, .stream)
        XCTAssertEqual(try Data(contentsOf: dst), try Data(contentsOf: src))
        let values = seen.value
        XCTAssertGreaterThan(values.count, 3)
        XCTAssertEqual(values.last, 1)
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dst.deletingLastPathComponent().path), ["big.bin"])
    }

    func testCloneCopyOnSameVolume() throws {
        let src = tmp.appending(path: "c.bin")
        try Data(repeating: 1, count: 4096).write(to: src)
        let dst = tmp.appending(path: "c2.bin")
        let method = try SaverFileCopier.copy(from: src, to: dst)
        XCTAssertTrue([.clone, .stream].contains(method))   // APFS'te .clone; başka FS'te akış yedeği
        XCTAssertEqual(try Data(contentsOf: dst), try Data(contentsOf: src))
    }

    func testRewriteOptionsAndClear() async throws {
        let a = try await source("a")
        _ = try await store.sync([a], options: options)
        try store.rewritePlaylistOptions(shuffle: false, hostExitOnStop: false)
        let list = try XCTUnwrap(store.currentPlaylist())
        XCTAssertFalse(list.shuffle); XCTAssertFalse(list.hostExitOnStop)
        try store.clear()
        XCTAssertNil(store.currentPlaylist())
        XCTAssertEqual(store.diskUsage(), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.url.path))
    }

    // MARK: Seçim

    private func wp(_ name: String, w: Int = 3840, h: Int = 2160, kind: WallpaperKind = .video, exists: Bool = true) throws -> WallpaperItem {
        let url = tmp.appending(path: "\(name).mov")
        if exists { try Data([0]).write(to: url) }
        return WallpaperItem(id: UUID(), name: name, path: url.path, kind: kind, addedAt: .now, byteSize: 1,
                             info: WallpaperMediaInfo(width: w, height: h, frameRate: 30, codec: "HEVC", hasAudio: false, duration: 5))
    }

    func testSelectionRules() throws {
        let a = try wp("a"), b = try wp("b"), img = try wp("i", kind: .image), gone = try wp("g", exists: false)
        let items = [a, b, img, gone]
        var wallpaper = WallpaperSettings()
        wallpaper.defaultItemID = b.id
        var saver = SaverSettings()
        wallpaper.playlistMode = .single
        XCTAssertEqual(SaverSelection.resolve(settings: saver, wallpaper: wallpaper, items: items).map(\.name), ["b"])
        wallpaper.playlistMode = .shuffle
        XCTAssertEqual(SaverSelection.resolve(settings: saver, wallpaper: wallpaper, items: items).map(\.name), ["a", "b"], "görüntü ve eksik dosya dışarıda")
        saver.source = .picked
        saver.pickedIDs = [b.id, gone.id, img.id, a.id]
        XCTAssertEqual(SaverSelection.resolve(settings: saver, wallpaper: wallpaper, items: items).map(\.name), ["b", "a"])
        let src = SaverSelection.sources(from: [a])
        XCTAssertEqual(src.first?.width, 3840)
        XCTAssertTrue(SaverSelection.isStale(playlist: nil, selection: src))
        XCTAssertFalse(SaverSelection.isStale(playlist: nil, selection: []))
    }

    func testFourKBadgeIncludesCinematicCrops() {
        func q(_ w: Int, _ h: Int) -> String { WallpaperMediaInfo(width: w, height: h, frameRate: 30, codec: "HEVC", hasAudio: false, duration: 1).qualityText }
        XCTAssertEqual(q(3840, 2160), "4K HEVC")
        XCTAssertEqual(q(3840, 1600), "4K HEVC", "sinematik 4K kırpma")
        XCTAssertEqual(q(4096, 2160), "4K HEVC")
        XCTAssertEqual(q(1920, 1080), "1080p HEVC")
        XCTAssertEqual(q(2560, 1440), "1440p HEVC")
        XCTAssertEqual(q(2160, 3840), "4K HEVC", "dikey 4K")
    }
}

/// Test yardımcısı: kilitli, Sendable değer kutusu.
final class LockedBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ body: (inout T) -> Void) { lock.lock(); defer { lock.unlock() }; body(&stored) }
}
