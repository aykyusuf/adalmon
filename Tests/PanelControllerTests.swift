import AppKit
import XCTest
@testable import Adalmon

/// Panel denetleyicisi: aç / aynı öğede kapat / başka öğede değiştir, Esc ile kapanma, anahtar pencere ve etkinleştirme.
@MainActor
final class PanelControllerTests: XCTestCase {
    private func makeController() -> (PanelController, AppModel) {
        let model = AppModel()
        let controller = PanelController(model: model, openApp: {}, openSettings: {})
        return (controller, model)
    }

    private func spin(_ s: TimeInterval = 0.15) { RunLoop.current.run(until: Date(timeIntervalSinceNow: s)) }

    func testOpenToggleSwitchAndEscape() throws {
        let (controller, model) = makeController()
        let a = NSStatusBar.system.statusItem(withLength: 40)
        let b = NSStatusBar.system.statusItem(withLength: 40)
        defer { NSStatusBar.system.removeStatusItem(a); NSStatusBar.system.removeStatusItem(b); controller.close() }
        let buttonA = try XCTUnwrap(a.button)
        let buttonB = try XCTUnwrap(b.button)
        buttonA.title = "A"; buttonB.title = "B"
        spin()
        var activations = 0
        controller.activateApp = { activations += 1 }

        let routeA = PanelRoute(itemKey: "item.A", kind: .cpu)
        let wasActive = NSApp.isActive
        controller.click(on: buttonA, route: routeA)
        spin()
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.route, routeA)
        XCTAssertTrue(model.panelVisible)
        XCTAssertEqual(model.panelKind, .cpu)
        XCTAssertTrue(controller.windowForTesting.canBecomeKey, "Esc için panel anahtar pencere olabilmeli")
        if !wasActive { XCTAssertEqual(activations, 1, "başka uygulama önde iken Esc için uygulama etkinleştirilir") }
        XCTAssertTrue(controller.windowForTesting.isKeyWindow, "açılınca anahtar pencere olmalı")

        // Başka öğeye tıklama: pencere kapanıp açılmaz, içerik değişir, panel yeni düğmeye taşınır.
        let frameBefore = controller.windowForTesting.frame
        controller.click(on: buttonB, route: PanelRoute(itemKey: "item.B", kind: .network))
        spin()
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.route?.kind, .network)
        XCTAssertEqual(model.panelKind, .network)
        XCTAssertEqual(controller.windowForTesting.frame.width, frameBefore.width, accuracy: 0.5, "genişlik sabit")
        XCTAssertTrue(model.panelVisible)

        // Birleşik görünüm bağlantısı: aynı düğmede içerik türü değişir.
        controller.setKind(.combined)
        XCTAssertEqual(model.panelKind, .combined)
        XCTAssertEqual(controller.route?.kind, .combined)

        // Aynı öğe + aynı içerik: kapat.
        controller.click(on: buttonB, route: PanelRoute(itemKey: "item.B", kind: .combined))
        spin()
        XCTAssertFalse(controller.isVisible)
        XCTAssertNil(controller.route)
        XCTAssertFalse(model.panelVisible)

        // Esc (cancelOperation) kapatır.
        controller.click(on: buttonA, route: routeA)
        spin()
        XCTAssertTrue(controller.isVisible)
        controller.windowForTesting.cancelOperation(nil)
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(model.panelVisible)
    }

    func testEscapeKeyEventClosesPanel() throws {
        let (controller, _) = makeController()
        let item = NSStatusBar.system.statusItem(withLength: 40)
        defer { NSStatusBar.system.removeStatusItem(item); controller.close() }
        let button = try XCTUnwrap(item.button)
        button.title = "A"
        spin()
        controller.activateApp = {}
        controller.click(on: button, route: PanelRoute(itemKey: "item.A", kind: .disk))
        spin()
        XCTAssertTrue(controller.isVisible)
        let esc = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: controller.windowForTesting.windowNumber, context: nil,
                                                 characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(esc)
        XCTAssertFalse(controller.isVisible, "Esc tuşu paneli kapatmalı")
    }
}
