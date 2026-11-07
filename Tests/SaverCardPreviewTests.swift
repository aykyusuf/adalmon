import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Ekran koruyucu + kilit ekranı kartını (iki kip, Gelişmiş açık) koyu görünümde çizip PNG yazar.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class SaverCardPreviewTests: XCTestCase {
    func testRenderSaverCard() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = FileManager.default.temporaryDirectory.appending(path: "saver-prev-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let suite = "adalmon.saver.preview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: tmp); defaults.removePersistentDomain(forName: suite) }

        // Kurulu paket (sahte) + videolar
        let embedded = tmp.appending(path: "App/AdalmonSaver.saver")
        try FileManager.default.createDirectory(at: embedded.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": SaverPaths.bundleIdentifier, "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", "CFBundleExecutable": "AdalmonSaver"]
        (info as NSDictionary).write(to: embedded.appending(path: "Contents/Info.plist"), atomically: true)
        try Data("code".utf8).write(to: embedded.appending(path: "Contents/MacOS/AdalmonSaver"))

        let controller = WallpaperController(isHeadless: true, screenProvider: { [] }, occlusionProvider: { _ in [:] })
        let service = WallpaperService(directory: tmp.appending(path: "Wallpapers"), defaults: defaults, controller: controller,
                                       installer: AerialInstaller(root: tmp.appending(path: "no-aerials"), supportDirectory: tmp))
        var files: [URL] = []
        for (i, name) in ["Okyanus", "Şehir gecesi", "Orman", "Çöl"].enumerated() {
            let v = tmp.appending(path: "\(name).mov"); try await TinyMedia.video(at: v, width: 160, height: 100, frames: 8, hue: CGFloat(i) * 0.25 + 0.1); files.append(v)
        }
        await service.importFiles(files)
        service.settings.playlistMode = .sequence
        service.settings.experimentalAerialAcknowledged = true
        service.settings.showInSystem = true

        func makeSaver(installed: Bool, selected: Bool?) throws -> SaverService {
            let installer = SaverInstaller(embeddedURL: embedded, installDirectory: tmp.appending(path: "ScreenSavers-\(UUID().uuidString)"))
            if installed { try installer.install() }
            return SaverService(installer: installer, store: SaverContentStore(directory: tmp.appending(path: "Saver-\(UUID().uuidString)")), defaults: defaults,
                                debounce: .seconds(60), hostKiller: {}, selectionProbe: { selected })
        }

        // 1) Henüz etkin değil (ilk kurulum)
        try await render(service, saver: try makeSaver(installed: false, selected: nil), name: "ux-saver-0-notinstalled", dir: dir)
        // 2) Kurulu, seçili: Duvar kâğıdıyla aynı
        let same = try makeSaver(installed: true, selected: true)
        try await render(service, saver: same, name: "ux-saver-1-same", dir: dir)
        // 3) Kurulu ama seçili değil
        try await render(service, saver: try makeSaver(installed: true, selected: false), name: "ux-saver-2-notselected", dir: dir)
        // 4) Farklı videolar
        let picked = try makeSaver(installed: true, selected: true)
        picked.settings.source = .picked
        picked.settings.pickedIDs = [service.items[0].id, service.items[2].id]
        try await render(service, saver: picked, name: "ux-saver-3-picked", dir: dir)
        // 5) Gelişmiş açık
        try await render(service, saver: same, name: "ux-saver-4-advanced", dir: dir, advanced: true)
    }

    private func render(_ service: WallpaperService, saver: SaverService, name: String, dir: URL, advanced: Bool = false) async throws {
        let size = NSSize(width: 900, height: advanced ? 720 : 560)
        let card = WallpaperSaverCardPreviewHost(wallpaper: service, saver: saver, advanced: advanced)
        let host = NSHostingView(rootView: card.padding(24).frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        await saver.refresh(wallpaper: service)
        try await Task.sleep(for: .seconds(1.5))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = dir.appending(path: "\(name).png")
        try png.write(to: url)
        print("SAVER_PREVIEW: \(url.path())")
        window.close()
    }
}

/// Önizleme: kartı, Gelişmiş açık/kapalı olarak çizer.
private struct WallpaperSaverCardPreviewHost: View {
    @Bindable var wallpaper: WallpaperService
    @Bindable var saver: SaverService
    var advanced: Bool

    var body: some View {
        WallpaperSaverCard(wallpaper: wallpaper, saver: saver, startExpanded: advanced)
    }
}
