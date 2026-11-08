import XCTest
import AppKit
@testable import Adalmon

@MainActor
final class OfficeWindowTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "office-window-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: Anahtarlar

    func testSettingsDefaultsAreAllOff() {
        let s = OfficeWindowSettings.default
        XCTAssertFalse(s.alwaysOnTop)
        XCTAssertFalse(s.allSpaces)
        XCTAssertFalse(s.transparentTitlebar)
        XCTAssertEqual(OfficeWindowSettings.load(from: defaults), .default)
    }

    func testSettingsRoundTrip() {
        let s = OfficeWindowSettings(alwaysOnTop: true, allSpaces: true, transparentTitlebar: true)
        XCTAssertEqual(OfficeWindowSettings.decode(s.encoded()), s)
        s.save(to: defaults)
        XCTAssertEqual(OfficeWindowSettings.load(from: defaults), s)
    }

    func testCorruptSettingsFallBackToDefault() {
        XCTAssertEqual(OfficeWindowSettings.decode(nil), .default)
        XCTAssertEqual(OfficeWindowSettings.decode(Data()), .default)
        XCTAssertEqual(OfficeWindowSettings.decode(Data("not json".utf8)), .default)
        XCTAssertEqual(OfficeWindowSettings.decode(Data(#"{"alwaysOnTop":"yes"}"#.utf8)), .default)
        XCTAssertEqual(OfficeWindowSettings.decode(Data("[1,2,3]".utf8)), .default)
        defaults.set("garbage", forKey: OfficeWindowSettings.defaultsKey)
        XCTAssertEqual(OfficeWindowSettings.load(from: defaults), .default)
    }

    func testPartialSettingsKeepKnownKeysAndDefaultTheRest() {
        let s = OfficeWindowSettings.decode(Data(#"{"allSpaces":true,"unknown":5}"#.utf8))
        XCTAssertEqual(s, OfficeWindowSettings(alwaysOnTop: false, allSpaces: true, transparentTitlebar: false))
    }

    func testLevelAndCollectionBehaviorMapping() {
        XCTAssertEqual(OfficeWindowSettings(alwaysOnTop: false).level, .normal)
        XCTAssertEqual(OfficeWindowSettings(alwaysOnTop: true).level, .floating)
        XCTAssertEqual(OfficeWindowSettings(allSpaces: false).collectionBehavior, [])
        XCTAssertTrue(OfficeWindowSettings(allSpaces: true).collectionBehavior.contains(.canJoinAllSpaces))
    }

    func testApplyToWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        OfficeWindowSettings(alwaysOnTop: true, allSpaces: true, transparentTitlebar: true).apply(to: window)
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)
        OfficeWindowSettings.default.apply(to: window)
        XCTAssertEqual(window.level, .normal)
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .visible)
    }

    // MARK: Çerçeve

    private let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)

    func testFrameRoundTrip() throws {
        let frame = NSRect(x: 100, y: 120, width: 800, height: 600)
        defaults.set(OfficeWindowFrame.encode(frame), forKey: OfficeWindowFrame.defaultsKey)
        let restored = OfficeWindowFrame.decode(defaults.object(forKey: OfficeWindowFrame.defaultsKey), visibleFrames: [screen])
        XCTAssertEqual(restored, frame)
    }

    func testCorruptFrameIsRejected() {
        let bad: [Any?] = [nil, "100 100 800 600", [1, 2, 3], [1, 2, 3, 4, 5], ["a", "b", "c", "d"], [0, 0, 0, 0], [0, 0, -5, 300],
                           [0, 0, Double.nan, 300], [0, 0, Double.infinity, 300], [0, 0, 1e9, 1e9], [1e12, 0, 800, 600], 42]
        for raw in bad {
            XCTAssertNil(OfficeWindowFrame.decode(raw, visibleFrames: [screen]), "kabul edilmemeli: \(String(describing: raw))")
        }
    }

    func testOffscreenFrameIsRejected() {
        XCTAssertNil(OfficeWindowFrame.decode(OfficeWindowFrame.encode(NSRect(x: 5_000, y: 5_000, width: 800, height: 600)), visibleFrames: [screen]))
        XCTAssertNil(OfficeWindowFrame.decode(OfficeWindowFrame.encode(NSRect(x: 100, y: 100, width: 800, height: 600)), visibleFrames: []))
        // Ekranla yalnızca birkaç piksel kesişen çerçeve (neredeyse tamamen dışarıda) kabul edilmez.
        XCTAssertNil(OfficeWindowFrame.decode(OfficeWindowFrame.encode(NSRect(x: 1_420, y: 100, width: 800, height: 600)), visibleFrames: [screen]))
    }

    func testTooSmallFrameIsRaisedToMinimum() throws {
        let raw = OfficeWindowFrame.encode(NSRect(x: 50, y: 50, width: 100, height: 100))
        let frame = try XCTUnwrap(OfficeWindowFrame.decode(raw, visibleFrames: [screen]))
        XCTAssertEqual(frame.size, OfficeWindowFrame.minSize)
    }

    func testDefaultFrameIsCenteredAndFitsSmallScreens() {
        let frame = OfficeWindowFrame.defaultFrame(visible: screen)
        XCTAssertEqual(frame.size, OfficeWindowFrame.defaultSize)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 1)
        let tiny = NSRect(x: 0, y: 0, width: 600, height: 400)
        XCTAssertTrue(tiny.contains(OfficeWindowFrame.defaultFrame(visible: tiny)))
    }

    // MARK: Denetleyici

    func testControllerIsSingleInstanceAndClosesCleanly() {
        let controller = OfficeWindowController(model: AppModel(), defaults: defaults)
        let window = controller.window
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(window.title, "Ajan ofisi")
        XCTAssertEqual(window.contentMinSize, NSSize(width: 480, height: 360))
        XCTAssertTrue(window.styleMask.contains(.resizable))

        controller.show()
        XCTAssertTrue(controller.isOpen)
        let content = window.contentViewController
        controller.show() // ikinci açma: aynı pencere, aynı içerik (yeni örnek yok)
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.contentViewController === content)

        controller.close()
        XCTAssertFalse(controller.isOpen, "kapanınca içerik (sahne) bırakılır")
        controller.show() // yeniden açılabilir, yine aynı pencere
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(controller.isOpen)
        controller.close()
    }

    func testControllerRestoresAndPersistsSettings() {
        OfficeWindowSettings(alwaysOnTop: true, allSpaces: true, transparentTitlebar: false).save(to: defaults)
        let controller = OfficeWindowController(model: AppModel(), defaults: defaults)
        XCTAssertEqual(controller.window.level, .floating)
        XCTAssertTrue(controller.window.collectionBehavior.contains(.canJoinAllSpaces))

        controller.state.settings.alwaysOnTop = false
        controller.state.settings.transparentTitlebar = true
        XCTAssertEqual(controller.window.level, .normal)
        XCTAssertTrue(controller.window.titlebarAppearsTransparent)
        XCTAssertEqual(OfficeWindowSettings.load(from: defaults),
                       OfficeWindowSettings(alwaysOnTop: false, allSpaces: true, transparentTitlebar: true))
    }

    func testControllerSurvivesCorruptDefaults() {
        defaults.set(Data("{{{".utf8), forKey: OfficeWindowSettings.defaultsKey)
        defaults.set("bozuk", forKey: OfficeWindowFrame.defaultsKey)
        let controller = OfficeWindowController(model: AppModel(), defaults: defaults)
        XCTAssertEqual(controller.state.settings, .default)
        XCTAssertEqual(controller.window.level, .normal)
        XCTAssertGreaterThanOrEqual(controller.window.frame.width, OfficeWindowFrame.minSize.width)
    }

    func testControllerPersistsFrameWhenClosed() throws {
        let controller = OfficeWindowController(model: AppModel(), defaults: defaults)
        controller.show()
        controller.window.setFrame(NSRect(x: 60, y: 80, width: 700, height: 500), display: false)
        controller.close()
        let screens = NSScreen.screens.map(\.visibleFrame)
        let stored = OfficeWindowFrame.decode(defaults.object(forKey: OfficeWindowFrame.defaultsKey), visibleFrames: screens)
        // Test makinesinde ekran yoksa (headless) çerçeve görünür sayılmaz; yalnızca ekran varken kesin denetle.
        if !screens.isEmpty { XCTAssertEqual(stored?.size, NSSize(width: 700, height: 500)) }
    }

    func testRouterOpensOfficeWindowRegardlessOfDockMode() {
        var opened = 0
        for dock in [true, false] {
            let router = SettingsRouter(isDockModeOn: { dock })
            router.attach(showMainWindow: {}, showSettingsWindow: {}, showOfficeWindow: { opened += 1 })
            router.openOfficeWindow()
        }
        XCTAssertEqual(opened, 2)
    }
}
