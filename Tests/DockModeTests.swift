import XCTest
@testable import Adalmon

@MainActor
final class DockModeTests: XCTestCase {
    private let key = "showInDock"

    /// Test ana bilgisayardaki gerçek uygulamayı çalıştırdığından kullanıcının ayarını geri yükler.
    private func withSavedPreference(_ body: () -> Void) {
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        body()
    }

    func testDefaultsToOff() {
        withSavedPreference {
            UserDefaults.standard.removeObject(forKey: key)
            XCTAssertFalse(Preferences().showInDock)
            XCTAssertEqual(DockModeController.launchPolicy, .accessory)
        }
    }

    func testPersistsAcrossInstances() {
        withSavedPreference {
            let prefs = Preferences()
            prefs.showInDock = true
            XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
            XCTAssertTrue(Preferences().showInDock)
            XCTAssertEqual(DockModeController.launchPolicy, .regular)
            prefs.showInDock = false
            XCTAssertFalse(Preferences().showInDock)
            XCTAssertEqual(DockModeController.launchPolicy, .accessory)
        }
    }
}
