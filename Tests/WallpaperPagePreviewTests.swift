import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Duvar kâğıdı sayfasını sahte (minik, sentetik) içerikle koyu görünümde çizip PNG yazar.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class WallpaperPagePreviewTests: XCTestCase {
    func testRenderWallpaperPage() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = FileManager.default.temporaryDirectory.appending(path: "wp-prev-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let suite = "adalmon.wp.preview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: tmp); defaults.removePersistentDomain(forName: suite) }

        let screens: [WallpaperController.LiveScreen] = [
            .init(info: WallpaperScreenInfo(key: "A", name: "Dahili Liquid Retina XDR", pixelSize: CGSize(width: 3024, height: 1964), scale: 2,
                                            cgBounds: CGRect(x: 0, y: 0, width: 1512, height: 982), isMain: true), frame: NSRect(x: 0, y: 0, width: 1512, height: 982)),
            .init(info: WallpaperScreenInfo(key: "B", name: "DELL U2723QE", pixelSize: CGSize(width: 3840, height: 2160), scale: 2,
                                            cgBounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080), isMain: false), frame: NSRect(x: 1512, y: 0, width: 1920, height: 1080)),
        ]
        let controller = WallpaperController(isHeadless: true, screenProvider: { screens }, occlusionProvider: { _ in [:] })
        let service = WallpaperService(directory: tmp.appending(path: "Wallpapers"), defaults: defaults, controller: controller,
                                       installer: AerialInstaller(root: tmp.appending(path: "no-aerials"), supportDirectory: tmp))
        var files: [URL] = []
        for (i, name) in ["Okyanus", "Şehir gecesi"].enumerated() {
            let v = tmp.appending(path: "\(name).mov"); try await TinyMedia.video(at: v, width: 160, height: 100, frames: 8, hue: CGFloat(i) * 0.4 + 0.2); files.append(v)
        }
        for (i, name) in ["Dağ", "Çöl"].enumerated() {
            let p = tmp.appending(path: "\(name).png"); try TinyMedia.png(at: p, hue: CGFloat(i) * 0.5 + 0.1); files.append(p)
        }
        await service.importFiles(files)
        service.settings.enabled = true
        service.settings.sameOnAllScreens = false
        service.settings.playlistMode = .shuffle
        service.settings.perScreen = ["B": service.items[2].id]
        service.settings.experimentalAerialAcknowledged = true
        // Gösterim için: video bilgisini 1080p HEVC gibi göster (sentetik klip 160x100 H.264).
        service.testOverrideInfo(WallpaperMediaInfo(width: 1920, height: 1080, frameRate: 30, codec: "HEVC", hasAudio: false, duration: 20), forFirst: 1)
        controller.monitor.state = .init()
        controller.reevaluate(poll: false)
        try await render(service, name: "wp-playing", dir: dir)

        controller.monitor.state.onBattery = true
        controller.reevaluate(poll: false)
        try await render(service, name: "wp-paused-battery", dir: dir)
    }

    private func render(_ service: WallpaperService, name: String, dir: URL) async throws {
        let size = NSSize(width: 1000, height: 1750)
        let host = NSHostingView(rootView: WallpaperPage(service: service).frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(2))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = dir.appending(path: "\(name).png")
        try png.write(to: url)
        print("WALLPAPER_PREVIEW: \(url.path())")
        window.close()
    }
}
