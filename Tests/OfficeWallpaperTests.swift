import XCTest
@testable import Adalmon

/// Ofis duvar kâğıdı: kaynak seçimi (Codable, durum makinesi), politika eşdeğerliği, genel bakış kamerası, etiket eşiği.
/// Denetleyici PENCERESİZ (headless) sınanır: gerçek masaüstüne pencere konmaz.
@MainActor
final class OfficeWallpaperTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "wp-office-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    // MARK: Codable

    func testOldJSONWithoutSourceDecodesToVideo() throws {
        let old = #"{"enabled":true,"sameOnAllScreens":true,"playlistMode":"single","rotationMinutes":30}"#
        let s = try JSONDecoder().decode(WallpaperSettings.self, from: Data(old.utf8))
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.source, .video)
        XCTAssertEqual(s.office, OfficeWallpaperOptions())
    }

    func testCorruptSourceFallsBackToVideo() throws {
        let bad = #"{"enabled":true,"source":"hologram","office":{"lighting":"disco","labels":"always"}}"#
        let s = try JSONDecoder().decode(WallpaperSettings.self, from: Data(bad.utf8))
        XCTAssertEqual(s.source, .video)
        XCTAssertEqual(s.office.lighting, .auto)       // bozuk alan varsayılana düşer
        XCTAssertEqual(s.office.labels, .always)       // geçerli alan korunur
    }

    func testSourceRoundTrip() throws {
        var s = WallpaperSettings()
        s.source = .office
        s.office = OfficeWallpaperOptions(); s.office.lighting = .night; s.office.background = .light; s.office.labels = .never
        let back = try JSONDecoder().decode(WallpaperSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    // MARK: Kaynak planı (saf)

    func testSourcePlanTransitions() {
        var s = WallpaperSettings()
        XCTAssertEqual(WallpaperSourcePlan.active(for: s), .off)
        s.enabled = true
        XCTAssertEqual(WallpaperSourcePlan.active(for: s), .video)
        s.source = .office
        XCTAssertEqual(WallpaperSourcePlan.active(for: s), .office)
        XCTAssertEqual(WallpaperSourcePlan.video.stops(whenSwitchingTo: .office), [.video])
        XCTAssertEqual(WallpaperSourcePlan.video.starts(whenSwitchingTo: .office), [.office])
        XCTAssertEqual(WallpaperSourcePlan.office.stops(whenSwitchingTo: .video), [.office])
        XCTAssertEqual(WallpaperSourcePlan.office.stops(whenSwitchingTo: .off), [.office])
        XCTAssertEqual(WallpaperSourcePlan.video.stops(whenSwitchingTo: .off), [.video])
        XCTAssertTrue(WallpaperSourcePlan.off.starts(whenSwitchingTo: .off).isEmpty)
        XCTAssertFalse(WallpaperSourcePlan.video.runsOffice)
        XCTAssertFalse(WallpaperSourcePlan.office.runsVideo)
    }

    // MARK: Denetleyici (headless)

    private func screen(_ key: String, y: CGFloat = 0) -> WallpaperController.LiveScreen {
        .init(info: WallpaperScreenInfo(key: key, name: key, pixelSize: CGSize(width: 3024, height: 1964), scale: 2,
                                        cgBounds: CGRect(x: 0, y: y, width: 1512, height: 982), isMain: key == "a"),
              frame: NSRect(x: 0, y: 0, width: 1512, height: 982))
    }

    private func item() throws -> WallpaperItem {
        let url = tmp.appending(path: "v.mov")
        try Data("x".utf8).write(to: url)
        return WallpaperItem(id: UUID(), name: "v", path: url.path, kind: .video, addedAt: .now, byteSize: 1,
                             info: WallpaperMediaInfo(width: 1920, height: 1080, frameRate: 30, codec: "HEVC", hasAudio: false, duration: 10))
    }

    private func controller(_ screens: [WallpaperController.LiveScreen]) -> WallpaperController {
        let c = WallpaperController(isHeadless: true, screenProvider: { screens }, occlusionProvider: { _ in [:] })
        c.themeProvider = { .vector }
        return c
    }

    private func config(_ items: [WallpaperItem], source: WallpaperSource, enabled: Bool = true) -> WallpaperController.Config {
        var s = WallpaperSettings(); s.enabled = enabled; s.source = source; s.defaultItemID = items.first?.id
        return .init(settings: s, items: items)
    }

    func testSourceSwitchStateMachine() throws {
        let v = try item()
        let c = controller([screen("a"), screen("b", y: 982)])
        c.apply(config([v], source: .video))
        XCTAssertEqual(c.videoScreenKeys, ["a", "b"]); XCTAssertTrue(c.officeScreenKeys.isEmpty)
        c.apply(config([v], source: .office))
        XCTAssertTrue(c.videoScreenKeys.isEmpty, "ofise geçince video dilimleri tamamen kapanır")
        XCTAssertEqual(c.officeScreenKeys, ["a", "b"])
        XCTAssertEqual(c.summary.text, "Oynatılıyor · Ajan ofisi · 0 oturum")
        c.apply(config([v], source: .video))
        XCTAssertEqual(c.videoScreenKeys, ["a", "b"]); XCTAssertTrue(c.officeScreenKeys.isEmpty, "videoya dönünce ofis dilimleri kapanır")
        c.apply(config([v], source: .office))
        c.apply(config([v], source: .office, enabled: false))
        XCTAssertTrue(c.videoScreenKeys.isEmpty); XCTAssertTrue(c.officeScreenKeys.isEmpty)
        XCTAssertEqual(c.summary, .off); XCTAssertFalse(c.monitor.isStarted)
    }

    func testOfficeNeedsNoLibraryAndRemovedScreenDropsSlot() {
        var screens = [screen("a"), screen("b", y: 982)]
        let c = WallpaperController(isHeadless: true, screenProvider: { screens }, occlusionProvider: { _ in [:] })
        c.apply(config([], source: .office))
        XCTAssertEqual(c.officeScreenKeys, ["a", "b"])
        screens.removeLast()
        c.apply(config([], source: .office))
        XCTAssertEqual(c.officeScreenKeys, ["a"])
    }

    /// Aynı girdiler/sebepler: ofis kaynağı video kaynağıyla birebir aynı duraklatma sonuçlarını verir.
    func testPolicyParityWithVideo() throws {
        let v = try item()
        struct Case { var name: String; var edit: (WallpaperController) -> Void }
        let cases: [Case] = [
            Case(name: "pil") { $0.monitor.state.onBattery = true },
            Case(name: "düşük güç") { $0.monitor.state.lowPower = true },
            Case(name: "bellek") { $0.monitor.state.memoryCritical = true },
            Case(name: "termal") { $0.monitor.state.thermalSerious = true },
            Case(name: "uyku") { $0.monitor.state.displayAsleep = true },
            Case(name: "yok") { _ in },
        ]
        for tc in cases {
            let cv = controller([screen("a")]), co = controller([screen("a")])
            tc.edit(cv); tc.edit(co)
            cv.apply(config([v], source: .video)); co.apply(config([v], source: .office))
            XCTAssertEqual(cv.screenStatuses.first?.decision, co.screenStatuses.first?.decision, tc.name)
            XCTAssertEqual(co.officeSlotState("a")?.decision, co.screenStatuses.first?.decision, tc.name)
        }
        let c = controller([screen("a")])
        c.monitor.state.onBattery = true
        c.apply(config([], source: .office))
        XCTAssertEqual(c.summary.text, "Duraklatıldı: pilde")
        var cfg = c.config; cfg.settings.rules.pauseOnBattery = false
        c.apply(cfg)
        XCTAssertTrue(c.summary.isPlaying)
        c.apply(.init(settings: cfg.settings, items: [], override: .forcePause))
        XCTAssertEqual(c.summary.text, "Duraklatıldı: elle")
    }

    func testOcclusionCoversOfficeAndPollingFollowsOffice() {
        let covered = ["a": OcclusionCheck.Result(coverage: 0.95, fullScreen: false)]
        let c = WallpaperController(isHeadless: true, screenProvider: { [self] in [screen("a")] }, occlusionProvider: { _ in covered })
        c.apply(config([], source: .office))
        XCTAssertEqual(c.summary.text, "Duraklatıldı: masaüstü örtülü")
        var cfg = c.config; cfg.settings.rules.pauseWhenDesktopHidden = false
        c.apply(cfg)
        XCTAssertTrue(c.summary.isPlaying)
    }

    func testCPUGateAppliesToOffice() {
        let c = controller([screen("a")])
        c.apply(config([], source: .office))
        let t0 = Date()
        for i in 0...32 { c.ingestCPU(0.95, at: t0.addingTimeInterval(Double(i))) }
        XCTAssertEqual(c.summary.text, "Duraklatıldı: CPU çok yoğun")
    }

    func testFeedMembersAndAgentsDisabledShowsEmptyScene() {
        let session = AgentSession(id: "s1", project: "adalmon", model: "claude-opus-4-8", status: .thinking, startedAt: .now, lastEventAt: .now, subagents: [])
        var enabled = true
        let c = controller([screen("a")])
        c.officeFeed = OfficeWallpaperFeed { OfficeFeedSnapshot(members: OfficeMember.members(from: [session]), agentsEnabled: enabled) }
        c.apply(config([], source: .office))
        XCTAssertEqual(c.officeSlotState("a")?.members.count, 1)
        XCTAssertEqual(c.summary.text, "Oynatılıyor · Ajan ofisi · 1 oturum")
        enabled = false
        c.refreshOfficeFeed()
        XCTAssertEqual(c.officeSlotState("a")?.members.count, 0, "ajan özelliği kapalıyken sahne boş")
        XCTAssertEqual(c.summary.text, "Oynatılıyor · Ajan ofisi · ajan özelliği kapalı")
    }

    func testVideoPathUnaffectedByOfficeFeed() throws {
        let c = controller([screen("a")])
        c.officeFeed = OfficeWallpaperFeed { OfficeFeedSnapshot() }
        c.apply(config([try item()], source: .video))
        XCTAssertEqual(c.summary.text, "Oynatılıyor · 1080p HEVC · tahmini enerji düşük")
        XCTAssertTrue(c.officeScreenKeys.isEmpty)
    }

    // MARK: Kamera

    private func sizes(_ n: Int) -> [OfficeRoomSize] { (0..<n).map { OfficeRoomSize(id: "r\($0)", width: 320, height: 220) } }

    func testOverviewFitsAllRoomsCenteredForCountsAndAspects() {
        let views: [CGSize] = [CGSize(width: 1920, height: 1080), CGSize(width: 2560, height: 1080), CGSize(width: 1280, height: 720)]
        for count in [1, 3, 10] {
            for view in views {
                let arr = OfficeWallpaperCamera.bestArrangement(sizes(count), view: view)
                XCTAssertEqual(arr.cells.count, count)
                let cam = OfficeWallpaperCamera.overview(content: arr.contentSize, view: view, integerOnly: false)
                let z = Double(cam.zoom)
                XCTAssertLessThanOrEqual(arr.contentWidth * z, view.width * (1 - 2 * OfficeWallpaperCamera.paddingFraction) + 0.01, "\(count) \(view)")
                XCTAssertLessThanOrEqual(arr.contentHeight * z, view.height * (1 - 2 * OfficeWallpaperCamera.paddingFraction) + 0.01, "\(count) \(view)")
                XCTAssertEqual(cam.center.x, arr.contentWidth / 2, accuracy: 0.001)
                XCTAssertEqual(cam.center.y, arr.contentHeight / 2, accuracy: 0.001)
                // hücreler çakışmaz ve içerik sınırları içindedir
                for (i, a) in arr.cells.enumerated() {
                    XCTAssertGreaterThanOrEqual(a.x, 0); XCTAssertLessThanOrEqual(a.x + a.width, arr.contentWidth + 0.001)
                    for b in arr.cells[(i + 1)...] { XCTAssertFalse(a.rect.intersects(b.rect), "\(count) \(view)") }
                }
            }
        }
    }

    func testOverviewColumnsFollowAspect() {
        let wide = OfficeWallpaperCamera.bestArrangement(sizes(3), view: CGSize(width: 2560, height: 1080))
        let video = OfficeWallpaperCamera.bestArrangement(sizes(3), view: CGSize(width: 1000, height: 1400))
        XCTAssertEqual(wide.columns, 3)
        XCTAssertLessThan(video.columns, wide.columns)
        let ten = OfficeWallpaperCamera.bestArrangement(sizes(10), view: CGSize(width: 1920, height: 1080))
        XCTAssertGreaterThan(ten.columns, 1)
    }

    func testOverviewZoomCapsAndShrinksBelowOne() {
        let small = OfficeWallpaperCamera.overview(content: CGSize(width: 340, height: 240), view: CGSize(width: 3000, height: 2000), integerOnly: false)
        XCTAssertEqual(Double(small.zoom), OfficeWallpaperCamera.maxZoom)
        let huge = OfficeWallpaperCamera.overview(content: CGSize(width: 3000, height: 2000), view: CGSize(width: 1000, height: 700), integerOnly: false)
        XCTAssertLessThan(huge.zoom, 1, "çok oda küçük ekranda 1x altına iner (kırpılmaz)")
        let pixel = OfficeWallpaperCamera.overview(content: CGSize(width: 400, height: 300), view: CGSize(width: 1000, height: 700), integerOnly: true)
        XCTAssertEqual(pixel.zoom, pixel.zoom.rounded())
    }

    func testPackedRowsAreCenteredAndHaveNoColumnHoles() {
        let mixed = [OfficeRoomSize(id: "a", width: 300, height: 200), OfficeRoomSize(id: "b", width: 400, height: 220), OfficeRoomSize(id: "c", width: 300, height: 200)]
        let arr = OfficeWallpaperCamera.packed(mixed, columns: 2)
        let gap = OfficeRoomArranger.gap, m = OfficeRoomArranger.margin
        XCTAssertEqual(arr.cells[1].x - (arr.cells[0].x + arr.cells[0].width), gap, accuracy: 0.001, "satır içinde bitişik")
        XCTAssertEqual(arr.contentWidth, 300 + 400 + gap + 2 * m, accuracy: 0.001)
        // tek odalı son satır ortalı
        XCTAssertEqual(arr.cells[2].x, m + (arr.contentWidth - 2 * m - 300) / 2, accuracy: 0.001)
        XCTAssertEqual(arr.contentHeight, m + 220 + gap + 200 + m, accuracy: 0.001)
    }

    // MARK: Etiket eşiği

    func testLabelThresholds() {
        XCTAssertFalse(OfficeWallpaperCamera.showsLabels(.auto, zoom: 1.49))
        XCTAssertTrue(OfficeWallpaperCamera.showsLabels(.auto, zoom: 1.5))
        XCTAssertTrue(OfficeWallpaperCamera.showsLabels(.always, zoom: 0.3))
        XCTAssertFalse(OfficeWallpaperCamera.showsLabels(.never, zoom: 6))
        XCTAssertFalse(OfficeWallpaperCamera.showsBubbles(.auto, zoom: 1.9))
        XCTAssertTrue(OfficeWallpaperCamera.showsBubbles(.auto, zoom: 2))
        XCTAssertFalse(OfficeWallpaperCamera.showsBubbles(.never, zoom: 6))
    }

    // MARK: Sahne

    func testSceneOverviewShowsAllRoomsAndRespectsLabelPolicy() throws {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let scene = OfficeScene(assets: assets, size: CGSize(width: 1280, height: 720), theme: .vector)
        scene.wallpaperLabels = .never
        let sessions = (0..<6).map { AgentSession(id: "s\($0)", project: "p\($0)", model: "claude-opus-4-8", status: .thinking, startedAt: .now, lastEventAt: .now, subagents: []) }
        scene.apply(members: OfficeMember.members(from: sessions), animated: false)
        XCTAssertEqual(scene.roomCount, 6)
        XCTAssertEqual(scene.visibleRoomCount, 6, "genel bakışta tüm odalar görünür")
        XCTAssertNil(scene.selectedRoomID)
        let cell = scene.arrangement.contentSize
        XCTAssertLessThanOrEqual(cell.width * scene.zoom, 1280 + 0.5)
        XCTAssertLessThanOrEqual(cell.height * scene.zoom, 720 + 0.5)
        scene.shutdown()
    }

    func testAnimationIdleWhenNoAgents() throws {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let scene = OfficeScene(assets: assets, size: CGSize(width: 1280, height: 720), theme: .vector)
        scene.wallpaperLabels = .auto
        scene.apply(members: [], animated: false)
        XCTAssertFalse(scene.isAnimating, "ajan yokken sahne statik")
        scene.shutdown()
    }
}
