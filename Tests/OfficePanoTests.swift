import XCTest
import CoreGraphics
@testable import Adalmon

@MainActor
final class OfficePanoTests: XCTestCase {
    // MARK: Karar mantığı

    func testPanoModeDecision() {
        XCTAssertTrue(OfficePanoMode.auto.isActive(fullScreen: true))
        XCTAssertFalse(OfficePanoMode.auto.isActive(fullScreen: false))
        XCTAssertTrue(OfficePanoMode.always.isActive(fullScreen: false))
        XCTAssertTrue(OfficePanoMode.always.isActive(fullScreen: true))
        XCTAssertFalse(OfficePanoMode.off.isActive(fullScreen: true))
        XCTAssertFalse(OfficePanoMode.off.isActive(fullScreen: false))
    }

    func testChromeVisibilityTimer() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        // Pencere (tam ekran değil): hep görünür, imleç hiç gizlenmez.
        XCTAssertTrue(OfficeChromeVisibility.stripVisible(fullScreen: false, now: t0.addingTimeInterval(60), lastActivity: t0, pointerOnStrip: false))
        XCTAssertFalse(OfficeChromeVisibility.cursorHidden(fullScreen: false, now: t0.addingTimeInterval(60), lastActivity: t0, pointerOnStrip: false))
        // Tam ekran: 3 sn'ye kadar görünür, sonra gizli.
        XCTAssertTrue(OfficeChromeVisibility.stripVisible(fullScreen: true, now: t0.addingTimeInterval(2.9), lastActivity: t0, pointerOnStrip: false))
        XCTAssertFalse(OfficeChromeVisibility.stripVisible(fullScreen: true, now: t0.addingTimeInterval(3), lastActivity: t0, pointerOnStrip: false))
        XCTAssertFalse(OfficeChromeVisibility.cursorHidden(fullScreen: true, now: t0.addingTimeInterval(2), lastActivity: t0, pointerOnStrip: false))
        XCTAssertTrue(OfficeChromeVisibility.cursorHidden(fullScreen: true, now: t0.addingTimeInterval(4), lastActivity: t0, pointerOnStrip: false))
        // İmleç şeritteyken şerit kalır, imleç gizlenmez.
        XCTAssertTrue(OfficeChromeVisibility.stripVisible(fullScreen: true, now: t0.addingTimeInterval(30), lastActivity: t0, pointerOnStrip: true))
        XCTAssertFalse(OfficeChromeVisibility.cursorHidden(fullScreen: true, now: t0.addingTimeInterval(30), lastActivity: t0, pointerOnStrip: true))
        // Sonraki gizlenme anı.
        XCTAssertEqual(OfficeChromeVisibility.nextHide(fullScreen: true, now: t0.addingTimeInterval(1), lastActivity: t0), t0.addingTimeInterval(3))
        XCTAssertNil(OfficeChromeVisibility.nextHide(fullScreen: true, now: t0.addingTimeInterval(5), lastActivity: t0))
        XCTAssertNil(OfficeChromeVisibility.nextHide(fullScreen: false, now: t0, lastActivity: t0))
        XCTAssertEqual(OfficeChromeVisibility.fadeDuration, 0.25)
    }

    func testBurnInOffsetStepsAndBounds() {
        let base = Date(timeIntervalSinceReferenceDate: 300 * 1000)
        XCTAssertEqual(OfficePanoBurnIn.offset(at: base), OfficePanoBurnIn.offset(at: base.addingTimeInterval(299)))
        XCTAssertNotEqual(OfficePanoBurnIn.offset(at: base), OfficePanoBurnIn.offset(at: base.addingTimeInterval(300)))
        var seen = Set<[Double]>()
        for i in -5..<40 {
            let o = OfficePanoBurnIn.offset(at: base.addingTimeInterval(Double(i) * 300))
            XCTAssertTrue((0...8).contains(o.width) && (0...8).contains(o.height))
            seen.insert([o.width, o.height])
        }
        XCTAssertEqual(seen.count, 4)
    }

    func testPanoText() {
        let tz = TimeZone(identifier: "UTC")!
        XCTAssertEqual(OfficePanoText.time(Date(timeIntervalSince1970: 3600 * 9 + 60 * 5), timeZone: tz), "09:05")
        let m = [OfficeMember(id: "a", parentID: nil, kind: .session, label: "a", badge: .sonnet, status: .thinking, groupIndex: 0),
                 OfficeMember(id: "b", parentID: "a", kind: .subagent, label: "b", badge: .haiku, status: .idle, groupIndex: 0),
                 OfficeMember(id: "c", parentID: nil, kind: .session, label: "c", badge: .opus, status: .tool("Edit"), groupIndex: 1)]
        XCTAssertEqual(OfficePanoText.summary(members: m), "2 oturum · 3 ajan · 2 çalışıyor")
        let next = OfficePanoClock.nextMinute(after: Date(timeIntervalSinceReferenceDate: 125.5))
        XCTAssertEqual(next.timeIntervalSinceReferenceDate, 180)
    }

    // MARK: Uyanık tut

    @MainActor
    final class FakeAssertion: DisplaySleepAsserting {
        var acquires = 0, releases = 0
        private(set) var isHeld = false
        func acquire(reason: String) -> Bool { if !isHeld { acquires += 1 }; isHeld = true; return true }
        func release() { if isHeld { releases += 1 }; isHeld = false }
    }

    func testKeepAwakeLifecycle() {
        let fake = FakeAssertion()
        let k = OfficeKeepAwake(assertion: fake)
        k.update(setting: false, fullScreen: true, windowOpen: true)
        XCTAssertFalse(fake.isHeld)                                          // varsayılan: kapalı
        k.update(setting: true, fullScreen: false, windowOpen: true)
        XCTAssertFalse(fake.isHeld)                                          // tam ekran değil
        k.update(setting: true, fullScreen: true, windowOpen: true)
        k.update(setting: true, fullScreen: true, windowOpen: true)
        XCTAssertTrue(fake.isHeld)
        XCTAssertEqual(fake.acquires, 1)                                     // tekrar çağrı ikinci assertion açmaz
        k.update(setting: true, fullScreen: false, windowOpen: true)
        XCTAssertFalse(fake.isHeld)                                          // tam ekrandan çıkınca bırakılır
        k.update(setting: true, fullScreen: true, windowOpen: true)
        k.update(setting: false, fullScreen: true, windowOpen: true)
        XCTAssertFalse(fake.isHeld)                                          // ayar kapanınca
        k.update(setting: true, fullScreen: true, windowOpen: true)
        k.releaseAll()
        XCTAssertFalse(fake.isHeld)                                          // pencere kapanınca
        XCTAssertEqual(fake.acquires, 3)
        XCTAssertEqual(fake.releases, 3)
    }

    // MARK: Ayar uyumu

    func testSettingsNewFieldsBackwardCompatible() {
        let old = OfficeWindowSettings.decode(Data(#"{"alwaysOnTop":true}"#.utf8))
        XCTAssertTrue(old.alwaysOnTop)
        XCTAssertEqual(old.panoMode, .auto)
        XCTAssertTrue(old.showsClockSummary)
        XCTAssertFalse(old.keepAwake)
        let s = OfficeWindowSettings(panoMode: .always, showsClockSummary: false, keepAwake: true)
        XCTAssertEqual(OfficeWindowSettings.decode(s.encoded()), s)
        XCTAssertEqual(OfficeWindowSettings.decode(Data(#"{"keepAwake":"yes"}"#.utf8)), .default)
    }

    // MARK: Yerleşim (kamera kenar boşluğu)

    private let tall = OfficeRoomSize(id: "r", width: 400, height: 526)

    func testSingleRoomFitsHeightAndIsCentered() {
        let view = CGSize(width: 1920, height: 1080)
        let r = OfficePanoLayout.arrange([tall], view: view)
        let cell = r.arrangement.cells[0]
        let expectedZoom = view.height * (1 - 2 * OfficePanoLayout.insetY) / tall.height
        XCTAssertEqual(r.zoom, expectedZoom, accuracy: 1e-6)
        XCTAssertEqual(cell.x + cell.width / 2, r.arrangement.contentWidth / 2, accuracy: 1e-6)       // yatay ortalı
        XCTAssertEqual(cell.y, OfficePanoLayout.insetY * view.height / r.zoom, accuracy: 1e-6)        // dikey kenar boşluğu %3
        XCTAssertEqual(r.arrangement.contentSize.width * r.zoom, view.width, accuracy: 1e-6)          // içerik görünümü doldurur
    }

    func testWideScreenEqualSpacing() {
        let view = CGSize(width: 5120, height: 1440)       // 32:9
        let sizes = [OfficeRoomSize(id: "a", width: 400, height: 526), OfficeRoomSize(id: "b", width: 400, height: 526), OfficeRoomSize(id: "c", width: 400, height: 526)]
        let r = OfficePanoLayout.arrange(sizes, view: view)
        let c = r.arrangement.cells
        XCTAssertEqual(r.arrangement.columns, 3)
        let left = c[0].x, g1 = c[1].x - (c[0].x + c[0].width), g2 = c[2].x - (c[1].x + c[1].width)
        let right = r.arrangement.contentWidth - (c[2].x + c[2].width)
        XCTAssertEqual(g1, g2, accuracy: 1e-6)
        XCTAssertEqual(left, g1, accuracy: 1e-6)
        XCTAssertEqual(right, g1, accuracy: 1e-6)
        XCTAssertGreaterThan(g1, OfficeRoomArranger.gap)
    }

    func testPanoMarginSmallerThanDefault() {
        let view = CGSize(width: 1920, height: 1080)
        let pano = OfficePanoLayout.arrange([tall, tall], view: view)
        let normal = OfficeRoomArranger.best([tall, tall], viewWidth: view.width, viewHeight: view.height)
        // Vektör temada eski düzen tamsayı zoom'a göre sütun seçiyordu; pano kesirli sığmayı seçer (en az tamsayı zoom kadar).
        XCTAssertGreaterThanOrEqual(pano.zoom, Double(normal.zoom))
        XCTAssertEqual(pano.zoom, min(view.width * 0.96 / (800 + OfficeRoomArranger.gap), view.height * 0.94 / 526), accuracy: 1e-6)
        XCTAssertEqual(OfficePanoLayout.insetX, 0.02)
        XCTAssertEqual(OfficePanoLayout.insetY, 0.03)
        XCTAssertEqual(OfficePanoLayout.uiScale(viewHeight: 600), 1)
        XCTAssertEqual(OfficePanoLayout.uiScale(viewHeight: 1800), 2)
        XCTAssertGreaterThan(OfficePanoLayout.uiScale(viewHeight: 1080), 1)
    }

    // MARK: Arka plan

    func testBackdropPalettes() {
        let d = OfficeBackdropPalette.day, n = OfficeBackdropPalette.night
        for c in [d.top, d.bottom] { XCTAssertTrue((0.75...1.0).contains(OfficeBackdropPalette.luminance(c))) }
        for c in [n.top, n.bottom] { XCTAssertLessThan(OfficeBackdropPalette.luminance(c), 0.2) }
        XCTAssertGreaterThan(OfficeBackdropPalette.luminance(d.top), OfficeBackdropPalette.luminance(d.bottom))   // krem → bej
        XCTAssertGreaterThan(d.plankAlpha, 0); XCTAssertEqual(d.stars, 0)
        XCTAssertGreaterThan(n.stars, 0); XCTAssertEqual(n.plankAlpha, 0)
        XCTAssertLessThan(d.plankAlpha, 0.12)                                                                      // çok düşük kontrast
        XCTAssertEqual(OfficeLighting.crossfade, 1)
        for sz in [CGSize(width: 3840, height: 2160), CGSize(width: 5120, height: 1440), CGSize(width: 600, height: 1400)] {
            let t = OfficeBackdropPalette.textureSize(for: sz)
            XCTAssertLessThanOrEqual(max(t.width, t.height), 1280)
        }
        XCTAssertNotNil(OfficeBackdropRenderer.image(palette: .night, width: 160, height: 90))
    }

    func testWallpaperOfficeBackgroundDefault() throws {
        XCTAssertEqual(OfficeWallpaperOptions().background, .office)
        XCTAssertEqual(OfficeWallpaperBackground.office.title, "Ofis")
        XCTAssertEqual(OfficeWallpaperBackground.auto.title, "Otomatik")
        XCTAssertEqual(OfficeWallpaperBackground.auto.resolved(night: true), .dark)
        XCTAssertEqual(OfficeWallpaperBackground.auto.resolved(night: false), .light)
        XCTAssertEqual(OfficeWallpaperBackground.office.resolved(night: true), .office, "Otomatik dışındakiler değişmez")
        XCTAssertEqual(OfficeWallpaperBackground.office.style, .themed)
        XCTAssertEqual(OfficeWallpaperBackground.dark.style, .solid(OfficeRGB(r: 14.0 / 255, g: 16.0 / 255, b: 20.0 / 255)))
        let old = try JSONDecoder().decode(OfficeWallpaperOptions.self, from: Data(#"{"background":"light"}"#.utf8))
        XCTAssertEqual(old.background, .light)
    }

    func testSceneThemedBackdropOnlyForVector() throws {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let scene = OfficeScene(assets: assets, size: CGSize(width: 800, height: 500), theme: .vector)
        XCTAssertFalse(scene.themedBackdropActive)
        scene.setBackdropStyle(.themed)
        XCTAssertTrue(scene.themedBackdropActive)
        scene.setTheme(.pixel)
        XCTAssertFalse(scene.themedBackdropActive)                      // piksel tema: eski koyu zemin
        scene.panoMode = true
        XCTAssertEqual(scene.uiScale, 1)
        scene.setTheme(.vector)
        XCTAssertGreaterThanOrEqual(scene.uiScale, 1)
        scene.shutdown()
    }
}
