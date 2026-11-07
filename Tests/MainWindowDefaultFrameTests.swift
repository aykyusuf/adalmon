import AppKit
import XCTest
@testable import Adalmon

@MainActor
final class MainWindowDefaultFrameTests: XCTestCase {
    func testDefaultFrameIsEightyFivePercentCenteredAndCapped() {
        let visible = NSRect(x: 0, y: 40, width: 1512, height: 880)
        let f = MainWindowController.defaultFrame(visible: visible)
        XCTAssertEqual(f.width, (1512 * 0.85).rounded())
        XCTAssertEqual(f.height, (880 * 0.85).rounded())
        XCTAssertEqual(f.midX, visible.midX, accuracy: 1)
        XCTAssertEqual(f.midY, visible.midY, accuracy: 1)
        XCTAssertTrue(visible.contains(f))

        let huge = MainWindowController.defaultFrame(visible: NSRect(x: 0, y: 0, width: 3_440, height: 1_440))
        XCTAssertEqual(huge.width, 1_600)
        XCTAssertEqual(huge.height, 1_050)
    }

    func testDefaultFrameRespectsMinimumAndNeverExceedsScreen() {
        let small = NSRect(x: 100, y: 100, width: 1_000, height: 640) // 85% altı min içerikten küçük
        let f = MainWindowController.defaultFrame(visible: small)
        XCTAssertEqual(f.width, 940)
        XCTAssertEqual(f.height, 600)
        let tiny = MainWindowController.defaultFrame(visible: NSRect(x: 0, y: 0, width: 800, height: 500))
        XCTAssertEqual(tiny.size, NSSize(width: 800, height: 500))
    }

    func testMigrationEnlargesSmallSavedFrameOnceThenRespectsUserFrame() throws {
        let suite = "adalmon.windowframe.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let small = NSSize(width: 940, height: 652)
        let large = NSSize(width: 1_300, height: 800)
        XCTAssertTrue(MainWindowController.needsDefaultFrame(restored: false, defaults: defaults))
        // Eski küçük çerçeve kayıtlı ama geçiş yapılmadı: bir kez büyük boyuta çekilir.
        XCTAssertTrue(MainWindowController.needsDefaultFrame(restored: true, savedSize: small, defaults: defaults))
        XCTAssertTrue(MainWindowController.needsDefaultFrame(restored: true, savedSize: NSSize(width: 1_400, height: 700), defaults: defaults))
        // Zaten büyük kayıtlı çerçeve korunur.
        XCTAssertFalse(MainWindowController.needsDefaultFrame(restored: true, savedSize: large, defaults: defaults))
        defaults.set(true, forKey: MainWindowController.sizedKey)
        // Geçişten sonra kullanıcı küçültse bile dokunulmaz.
        XCTAssertFalse(MainWindowController.needsDefaultFrame(restored: true, savedSize: small, defaults: defaults))
        XCTAssertTrue(MainWindowController.needsDefaultFrame(restored: false, defaults: defaults))
        XCTAssertEqual(MainWindowController.sizedKey, "mainWindow.sizedV3")
    }

    func testShowAndReopenKeepWindowFrame() {
        let model = AppModel()
        let router = SettingsRouter(isDockModeOn: { true })
        let controller = MainWindowController(model: model, router: router)
        let wanted = NSRect(x: 80, y: 80, width: 1_380, height: 820)
        controller.frame = wanted
        controller.show()
        XCTAssertEqual(controller.frame.size.width, wanted.width, accuracy: 1, "içerik atanınca pencere en küçük boyuta inmemeli")
        XCTAssertEqual(controller.frame.size.height, wanted.height, accuracy: 1)
        controller.close()
        controller.show()
        XCTAssertEqual(controller.frame.size.width, wanted.width, accuracy: 1, "yeniden açılışta da korunmalı")
        XCTAssertEqual(controller.frame.size.height, wanted.height, accuracy: 1)
        controller.close()
    }
}
