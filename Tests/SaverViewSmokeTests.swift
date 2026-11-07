import AVFoundation
import ScreenSaver
import XCTest
@testable import Adalmon

/// Gerçek .saver paketini test sürecine yükler ve görünümü uçtan uca çalıştırır (geçici klasör, küçük video).
/// Gerçek /Users/Shared ve ekran koruyucu ayarlarına dokunulmaz.
@MainActor
final class SaverViewSmokeTests: XCTestCase {
    private var tmp: URL!
    private var cls: ScreenSaverView.Type!

    override func setUp() async throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "saver-view-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        setenv("ADALMON_SAVER_DIR_FOR_TESTS", tmp.path, 1)
        let bundle = try XCTUnwrap(Bundle(url: SaverInstaller.defaultEmbeddedURL))
        XCTAssertTrue(bundle.load())
        cls = try XCTUnwrap(bundle.principalClass as? ScreenSaverView.Type)
    }

    override func tearDown() async throws {
        unsetenv("ADALMON_SAVER_DIR_FOR_TESTS")
        try? FileManager.default.removeItem(at: tmp)
    }

    private func playerLayer(of view: NSView) -> AVPlayerLayer? { view.layer?.sublayers?.compactMap { $0 as? AVPlayerLayer }.first }

    private func prepare(videos: Int, hostExit: Bool = false) async throws {
        var sources: [SaverContentStore.Source] = []
        for i in 0..<videos {
            let url = tmp.appending(path: "src\(i).mov")
            try await TinyMedia.video(at: url, frames: 30, hue: CGFloat(i) * 0.3 + 0.1)
            sources.append(.init(id: UUID(), name: "v\(i)", url: url, byteSize: WallpaperMedia.fileSize(url), width: 128, height: 72, duration: 1))
        }
        let store = SaverContentStore(directory: tmp.appending(path: "Saver"))
        _ = try await store.sync(sources, options: .init(shuffle: true, hostExitOnStop: hostExit, appVersion: "t"))
    }

    private func waitUntil(_ timeout: Double = 4, _ cond: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond(), Date() < end { try? await Task.sleep(for: .milliseconds(50)) }
    }

    func testFullInstancePlaysMutedAndTearsDownOnStop() async throws {
        setenv("ADALMON_SAVER_DIR_FOR_TESTS", tmp.appending(path: "Saver").path, 1)
        try await prepare(videos: 2)
        let view = try XCTUnwrap(cls.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500), isPreview: false))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.startAnimation()
        let layer = try XCTUnwrap(playerLayer(of: view))
        let player = try XCTUnwrap(layer.player as? AVQueuePlayer, "tam boyutlu örnekte AVQueuePlayer olmalı")
        XCTAssertTrue(player.isMuted)
        XCTAssertEqual(layer.videoGravity, .resizeAspectFill)
        await waitUntil { player.currentItem != nil && player.rate > 0 }
        XCTAssertGreaterThan(player.rate, 0, "oynatmalı")
        XCTAssertEqual(player.items().count >= 1, true)

        view.stopAnimation()
        XCTAssertNil(layer.player, "stopAnimation oynatıcıyı bırakmalı")
        XCTAssertTrue(player.items().isEmpty)
        view.stopAnimation()               // tekrar çağrı zararsız
        view.startAnimation()              // yeniden başlatılabilir
        XCTAssertNotNil(playerLayer(of: view)?.player)
        view.stopAnimation()
        XCTAssertNil(playerLayer(of: view)?.player)
    }

    func testSecondInstanceOnSameScreenReplacesFirst() async throws {
        setenv("ADALMON_SAVER_DIR_FOR_TESTS", tmp.appending(path: "Saver").path, 1)
        try await prepare(videos: 1)
        func make() throws -> (ScreenSaverView, NSWindow) {
            let v = try XCTUnwrap(cls.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500), isPreview: false))
            let w = NSWindow(contentRect: v.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = v
            return (v, w)
        }
        let (first, w1) = try make(), (second, w2) = try make()
        first.startAnimation()
        XCTAssertNotNil(playerLayer(of: first)?.player)
        second.startAnimation()          // host stopAnimation çağırmasa bile (macOS hatası) ilk örnek bırakılır
        XCTAssertNil(playerLayer(of: first)?.player, "yığılma: eski örnek durdurulmalı")
        XCTAssertNotNil(playerLayer(of: second)?.player)
        second.stopAnimation()
        _ = (w1, w2)
    }

    func testPreviewInstanceNeverStartsPlayerAndShowsPoster() async throws {
        setenv("ADALMON_SAVER_DIR_FOR_TESTS", tmp.appending(path: "Saver").path, 1)
        try await prepare(videos: 1)
        // Poster üretici verilmediği için test posteri elle yazılır
        let list = try XCTUnwrap(SaverPlaylist.load(from: tmp.appending(path: "Saver")))
        let posterName = list.items[0].id.uuidString + ".jpg"
        let frame = await WallpaperMedia.frameImage(tmp.appending(path: "src0.mov"), kind: .video, maxPixel: 128, at: 0)
        let cg = try XCTUnwrap(frame)
        try XCTUnwrap(WallpaperMedia.jpegData(cg)).write(to: tmp.appending(path: "Saver/\(posterName)"))
        var edited = list; edited.items[0].poster = posterName
        try edited.encoded().write(to: SaverPaths.playlistURL(in: tmp.appending(path: "Saver")))

        let view = try XCTUnwrap(cls.init(frame: NSRect(x: 0, y: 0, width: 296, height: 184), isPreview: true))
        view.startAnimation()
        XCTAssertNil(playerLayer(of: view)?.player, "önizlemede 4K çözme yok")
        XCTAssertNotNil(view.layer?.contents, "önizlemede poster görünmeli")
        // isPreview=false ama 0x0 çerçeve (macOS hatası) da önizleme sayılır
        let zero = try XCTUnwrap(cls.init(frame: .zero, isPreview: false))
        zero.startAnimation()
        XCTAssertNil(playerLayer(of: zero)?.player)
        view.stopAnimation(); zero.stopAnimation()
    }

    func testMissingPlaylistShowsMessageWithoutCrashing() throws {
        let view = try XCTUnwrap(cls.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500), isPreview: false))
        view.startAnimation()
        XCTAssertNil(playerLayer(of: view)?.player)
        let text = view.layer?.sublayers?.compactMap { $0 as? CATextLayer }.first
        XCTAssertEqual(text?.isHidden, false)
        view.stopAnimation()
    }
}
