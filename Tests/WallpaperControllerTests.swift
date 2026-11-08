import XCTest
@testable import Adalmon

/// Denetleyici kararları PENCERESİZ (headless) sınanır: gerçek masaüstüne pencere konmaz, gözlemci / zamanlayıcı kurulmaz.
@MainActor
final class WallpaperControllerTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "wp-ctl-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func screen(_ key: String, name: String, y: CGFloat = 0, main: Bool = false) -> WallpaperController.LiveScreen {
        .init(info: WallpaperScreenInfo(key: key, name: name, pixelSize: CGSize(width: 3024, height: 1964), scale: 2,
                                        cgBounds: CGRect(x: 0, y: y, width: 1512, height: 982), isMain: main),
              frame: NSRect(x: 0, y: 0, width: 1512, height: 982))
    }

    private func item(_ name: String, kind: WallpaperKind = .video, fps: Double = 30, codec: String = "HEVC") throws -> WallpaperItem {
        let url = tmp.appending(path: "\(name).\(kind == .video ? "mov" : "png")")
        try Data("x".utf8).write(to: url)
        return WallpaperItem(id: UUID(), name: name, path: url.path, kind: kind, addedAt: .now, byteSize: 1,
                             info: WallpaperMediaInfo(width: 1920, height: 1080, frameRate: fps, codec: codec, hasAudio: false, duration: 10))
    }

    private func controller(screens: [WallpaperController.LiveScreen], occlusion: [String: OcclusionCheck.Result] = [:]) -> WallpaperController {
        WallpaperController(isHeadless: true, screenProvider: { screens }, occlusionProvider: { _ in occlusion })
    }

    private func config(_ items: [WallpaperItem], enabled: Bool = true, edit: (inout WallpaperSettings) -> Void = { _ in }) -> WallpaperController.Config {
        var s = WallpaperSettings(); s.enabled = enabled; s.defaultItemID = items.first?.id
        edit(&s)
        return .init(settings: s, items: items)
    }

    func testDisabledMeansNothingExists() throws {
        let c = controller(screens: [screen("a", name: "Ana")])
        c.apply(config([try item("v")], enabled: false))
        XCTAssertEqual(c.summary, .off)
        XCTAssertTrue(c.screenStatuses.isEmpty)
        XCTAssertTrue(c.screens.isEmpty)
        XCTAssertFalse(c.monitor.isStarted)
    }

    func testPlayingStatusText() throws {
        let c = controller(screens: [screen("a", name: "Ana", main: true)])
        c.apply(config([try item("v")]))
        XCTAssertEqual(c.summary.text, "Oynatılıyor · 1080p HEVC · tahmini enerji düşük")
    }

    func testBatteryAndLowPowerPauseAndUserCanResume() throws {
        let c = controller(screens: [screen("a", name: "Ana")])
        c.monitor.state.onBattery = true
        c.apply(config([try item("v")]))
        XCTAssertEqual(c.summary.text, "Duraklatıldı: pilde")
        var cfg = c.config
        cfg.settings.rules.pauseOnBattery = false
        c.apply(cfg)
        XCTAssertTrue(c.summary.isPlaying, "kural kapatılınca devam eder")
        c.monitor.state.lowPower = true
        c.reevaluate(poll: false)
        XCTAssertEqual(c.summary.text, "Duraklatıldı: Düşük Güç Modu")
        cfg.override = .forcePlay
        c.apply(cfg)
        XCTAssertTrue(c.summary.isPlaying, "\"yine de oynat\" Düşük Güç kuralını yok sayar")
    }

    func testMemoryCriticalAndThermalPauseWithReasonAndResume() throws {
        let c = controller(screens: [screen("a", name: "Ana")])
        c.apply(config([try item("v")]))
        XCTAssertTrue(c.summary.isPlaying)
        c.monitor.state.memoryCritical = true
        c.reevaluate(poll: false)
        XCTAssertEqual(c.summary.text, "Duraklatıldı: bellek baskısı kritik")
        c.monitor.state.memoryCritical = false
        c.monitor.state.thermalSerious = true
        c.reevaluate(poll: false)
        XCTAssertEqual(c.summary.text, "Duraklatıldı: Mac ısındı")
        var cfg = c.config
        cfg.settings.rules.pauseOnThermal = false
        c.apply(cfg)
        XCTAssertTrue(c.summary.isPlaying, "kural kapatılınca devam eder")
        c.monitor.state.thermalSerious = false
        c.reevaluate(poll: false)
        XCTAssertTrue(c.summary.isPlaying)
    }

    func testHighCPUPausesAfterSustainedLoadAndResumesWithHysteresis() throws {
        let c = controller(screens: [screen("a", name: "Ana")])
        c.apply(config([try item("v")]))
        let t0 = Date.now
        for s in stride(from: 0.0, through: 28, by: 2) { c.ingestCPU(0.95, at: t0.addingTimeInterval(s)) }
        XCTAssertTrue(c.summary.isPlaying, "30 sn dolmadan durmaz")
        c.ingestCPU(0.95, at: t0.addingTimeInterval(30))
        XCTAssertEqual(c.summary.text, "Duraklatıldı: CPU çok yoğun")
        for s in stride(from: 32.0, through: 90, by: 2) { c.ingestCPU(0.70, at: t0.addingTimeInterval(s)) }
        XCTAssertEqual(c.summary.text, "Duraklatıldı: CPU çok yoğun", "%60-85 arası: duraklatılmış kalır")
        for s in stride(from: 92.0, through: 130, by: 2) { c.ingestCPU(0.10, at: t0.addingTimeInterval(s)) }
        XCTAssertTrue(c.summary.isPlaying, "%60 altına inince devam")
    }

    func testHighCPURuleOffIgnoresSamplesAndClearsPause() throws {
        let c = controller(screens: [screen("a", name: "Ana")])
        c.apply(config([try item("v")]))
        let t0 = Date.now
        for s in stride(from: 0.0, through: 30, by: 2) { c.ingestCPU(1.0, at: t0.addingTimeInterval(s)) }
        XCTAssertEqual(c.summary.text, "Duraklatıldı: CPU çok yoğun")
        var cfg = c.config
        cfg.settings.rules.pauseOnHighCPU = false
        c.apply(cfg)
        XCTAssertTrue(c.summary.isPlaying)
        XCTAssertNil(c.cpuGate.runStart)
        for s in stride(from: 32.0, through: 80, by: 2) { c.ingestCPU(1.0, at: t0.addingTimeInterval(s)) }
        XCTAssertTrue(c.summary.isPlaying)
        XCTAssertTrue(c.cpuGate.samples.isEmpty, "kural kapalıyken örnek tutulmaz")
    }

    func testDisabledWallpaperIgnoresCPUSamples() throws {
        let c = controller(screens: [screen("a", name: "Ana")])
        c.apply(config([try item("v")], enabled: false))
        c.ingestCPU(1.0)
        XCTAssertTrue(c.cpuGate.samples.isEmpty)
        XCTAssertEqual(c.summary, .off)
    }

    func testMonitorReadsInjectedMemoryAndThermalWithoutStarting() {
        var level: Int32? = 2
        let m = WallpaperSystemMonitor(memoryLevelReader: { level }, thermalReader: { .fair })
        XCTAssertFalse(m.refreshMemory(event: .warning), "uyarı seviyesi kritik sayılmaz")
        XCTAssertFalse(m.state.memoryCritical)
        level = 4
        XCTAssertTrue(m.refreshMemory(event: .critical))
        XCTAssertTrue(m.state.memoryCritical)
        level = 1
        XCTAssertTrue(m.refreshMemory(event: .normal))
        XCTAssertFalse(m.state.memoryCritical)
        // sysctl okunamazsa olay maskesi kullanılır.
        level = nil
        XCTAssertTrue(m.refreshMemory(event: .critical))
        XCTAssertTrue(m.state.memoryCritical)
        XCTAssertFalse(m.isStarted)
    }

    func testCoveredAndFullScreenPause() throws {
        var occ: [String: OcclusionCheck.Result] = ["a": .init(coverage: 0.95, fullScreen: false)]
        let c = WallpaperController(isHeadless: true, screenProvider: { [self] in [screen("a", name: "Ana")] }, occlusionProvider: { _ in occ })
        c.apply(config([try item("v")]))
        XCTAssertEqual(c.summary.text, "Duraklatıldı: masaüstü örtülü")
        occ = ["a": .init(coverage: 1, fullScreen: true)]
        c.reevaluate(poll: true)
        XCTAssertEqual(c.summary.text, "Duraklatıldı: tam ekran uygulama")
        occ = ["a": .init(coverage: 0.1, fullScreen: false)]
        c.reevaluate(poll: true)
        XCTAssertTrue(c.summary.isPlaying)
    }

    func testPerScreenAssignmentAndStatusRows() throws {
        let a = try item("a"), b = try item("b")
        let c = controller(screens: [screen("s1", name: "Ana", main: true), screen("s2", name: "Harici", y: -982)])
        c.apply(config([a, b]) { $0.sameOnAllScreens = false; $0.perScreen = ["s2": b.id] })
        XCTAssertEqual(c.screenStatuses.map(\.itemName), ["a", "b"])
        XCTAssertEqual(c.screens.count, 2)
    }

    func testScreenRemovalDropsStatusRow() throws {
        var screens = [screen("s1", name: "Ana"), screen("s2", name: "Harici")]
        let c = WallpaperController(isHeadless: true, screenProvider: { screens }, occlusionProvider: { _ in [:] })
        c.apply(config([try item("v")]))
        XCTAssertEqual(c.screenStatuses.count, 2)
        screens.removeLast()
        c.apply(c.config)
        XCTAssertEqual(c.screenStatuses.count, 1)
    }

    func testStillImageSummaryAndMissingFileFallback() throws {
        let img = try item("pic", kind: .image)
        let c = controller(screens: [screen("a", name: "Ana")])
        c.apply(config([img]))
        XCTAssertTrue(c.summary.text.hasPrefix("Sabit görüntü"))
        var missing = img; missing.path = tmp.appending(path: "yok.png").path
        c.apply(config([missing]))
        XCTAssertEqual(c.summary, .noContent)
    }

    func testPlaylistAdvanceChangesAssignedItem() throws {
        let a = try item("a"), b = try item("b")
        let c = controller(screens: [screen("s", name: "Ana")])
        c.apply(config([a, b]) { $0.playlistMode = .sequence; $0.defaultItemID = a.id })
        XCTAssertEqual(c.screenStatuses.first?.itemName, "a")
        c.advanceNow()
        XCTAssertEqual(c.screenStatuses.first?.itemName, "b")
    }
}

@MainActor
final class WallpaperServiceTests: XCTestCase {
    private var tmp: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "wp-svc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        suite = "adalmon.wp.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeService() -> WallpaperService {
        WallpaperService(directory: tmp.appending(path: "Wallpapers"), defaults: defaults, controller: WallpaperController(isHeadless: true, screenProvider: { [] }, occlusionProvider: { _ in [:] }),
                         installer: AerialInstaller(root: tmp.appending(path: "no-aerials"), supportDirectory: tmp))
    }

    func testDefaultsAreOffAndSafe() {
        let s = makeService()
        XCTAssertFalse(s.settings.enabled)
        XCTAssertEqual(s.settings.rules, WallpaperPauseRules())
        XCTAssertFalse(s.settings.experimentalAerialAcknowledged)
        XCTAssertEqual(s.controller.summary, .off)
    }

    func testImportPersistRemove() async throws {
        let png = tmp.appending(path: "p.png"); try TinyMedia.png(at: png)
        let txt = tmp.appending(path: "n.txt"); try Data("x".utf8).write(to: txt)
        let s = makeService()
        await s.importFiles([png, txt, png])
        XCTAssertEqual(s.items.count, 1, "yinelenen ve desteklenmeyen dosya eklenmez")
        XCTAssertEqual(s.settings.defaultItemID, s.items.first?.id)
        XCTAssertNotNil(s.message)
        // Kalıcılık
        let again = makeService()
        XCTAssertEqual(again.items.map(\.name), ["p"])
        let thumb = await again.thumbnail(for: again.items[0])
        XCTAssertNotNil(thumb)
        let id = again.items[0].id
        again.remove(id)
        XCTAssertTrue(again.items.isEmpty)
        XCTAssertNil(again.settings.defaultItemID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path), "kullanıcının özgün dosyası silinmez")
    }

    func testConvertAddsOptimizedCopyWithSizes() async throws {
        let v = tmp.appending(path: "big.mov"); try await TinyMedia.video(at: v, width: 128, height: 72, fps: 60, frames: 30)
        let s = makeService()
        await s.importFiles([v])
        let id = try XCTUnwrap(s.items.first?.id)
        s.convert(id)
        for _ in 0..<200 where s.items.count < 2 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(s.items.count, 2)
        let copy = try XCTUnwrap(s.items.last)
        XCTAssertTrue(copy.isOptimized)
        XCTAssertEqual(copy.originalByteSize, s.items[0].byteSize)
        XCTAssertEqual(copy.info?.codec, "HEVC")
        XCTAssertTrue(copy.path.hasPrefix(s.directory.path), "kopya Adalmon klasörüne yazılır")
        s.remove(copy.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path), "dönüştürülmüş kopya silinir")
    }
}
