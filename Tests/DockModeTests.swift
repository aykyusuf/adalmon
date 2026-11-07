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

    /// Regresyon: AppKit açılışta kendi varsayılan menüsünü (Apple + Adalmon) koyar; Dock modu bunu bizim tam menümüzle
    /// değiştirmeli (Görünüm ⌘1…⌘7, Düzen ⌘C/⌘V/⌘X/⌘A/⌘Z, ⌘F).
    func testApplyInstallsFullMainMenuEvenWhenAppKitAlreadyHasADefaultMenu() throws {
        let savedMenu = NSApp.mainMenu
        let savedPolicy = NSApp.activationPolicy()
        defer {
            NSApp.mainMenu = savedMenu
            NSApp.setActivationPolicy(savedPolicy)
        }
        // AppKit'in kurduğu varsayılan menüyü taklit et: yalnızca uygulama menüsü.
        let stub = NSMenu()
        let appItem = NSMenuItem(title: "Adalmon", action: nil, keyEquivalent: "")
        appItem.submenu = NSMenu(title: "Adalmon")
        stub.addItem(appItem)
        NSApp.mainMenu = stub

        let delegate = AppDelegate()
        let controller = DockModeController(
            prefs: Preferences(),
            makeMenu: { MainMenuBuilder.make(target: delegate) },
            closeMainWindow: {}, closeSettingsWindow: {})
        controller.apply(true)

        let menu = try XCTUnwrap(NSApp.mainMenu)
        XCTAssertFalse(menu === stub, "varsayılan menü bizimkiyle değişmeli")
        let titles = menu.items.map(\.title)
        for expected in ["Adalmon", "Düzen", "Görünüm", "Pencere", "Yardım"] {
            XCTAssertTrue(titles.contains(expected), "\(expected) menüsü yok: \(titles)")
        }

        // Görünüm: tüm sayfalar ⌘1…⌘7 (Süreçler ⌘6, Pil ⌘7).
        let view = try XCTUnwrap(menu.items.first { $0.title == "Görünüm" }?.submenu)
        let pageKeys = view.items.filter { $0.action == #selector(MainWindowCommands.selectSection(_:)) }
        XCTAssertEqual(pageKeys.map(\.keyEquivalent), ["1", "2", "3", "4", "5", "6", "7"])
        XCTAssertTrue(pageKeys.allSatisfy { $0.keyEquivalentModifierMask == .command })
        XCTAssertEqual(pageKeys[5].representedObject as? String, MainSection.processes.id)
        XCTAssertEqual(pageKeys[6].representedObject as? String, MainSection.battery.id)

        // Düzen: standart düzenleme kısayolları.
        let edit = try XCTUnwrap(menu.items.first { $0.title == "Düzen" }?.submenu)
        let keys = Dictionary(uniqueKeysWithValues: edit.items.filter { !$0.keyEquivalent.isEmpty && $0.keyEquivalentModifierMask == .command }
            .map { ($0.keyEquivalent, $0.action) })
        XCTAssertEqual(keys["c"], #selector(NSText.copy(_:)))
        XCTAssertEqual(keys["v"], #selector(NSText.paste(_:)))
        XCTAssertEqual(keys["x"], #selector(NSText.cut(_:)))
        XCTAssertEqual(keys["a"], #selector(NSText.selectAll(_:)))
        XCTAssertEqual(keys["z"], Selector(("undo:")))
        XCTAssertEqual(keys["f"], #selector(MainWindowCommands.focusSearch(_:)))

        // Aynı menü yeniden kurulmaz; Dock modu kapanınca tam menü kalkar (AppKit yerine kendi varsayılanını koyar).
        controller.apply(true)
        XCTAssertTrue(NSApp.mainMenu === menu)
        controller.apply(false)
        XCTAssertNil(controller.installedMenu)
        XCTAssertFalse(NSApp.mainMenu === menu, "Dock modu kapanınca tam menü kalkar")
    }
}
