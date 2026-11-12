import AppKit
import ObjectiveC
import XCTest

/// Test paketinin ilk yüklenen sınıfı (Info.plist `NSPrincipalClass`): testler sırasında kullanıcının ekranında pencere belirmesin.
///
/// Test sunucusu Adalmon.app'in kendisidir; birçok test gerçek `NSWindow`/`NSPanel` kurup öne getirir (ana pencere, ofis, panel,
/// pil parlaması, Saver önizlemesi...). `WindowGuard` bunları pencere sunucusuna gerçek alfa 0 ile gösterir: pencere "görünür"
/// (`isVisible`, anahtar pencere, `cacheDisplay`, görünüm hiyerarşisi aynı), ama ekranda hiçbir şey çizilmez ve uygulama
/// başka uygulamanın önüne geçmez. Üretim koduna dokunmaz; yalnızca test sürecinde, test paketi yüklenince kurulur.
///
/// Kapatma: `TEST_RUNNER_ADALMON_SCREEN_TESTS=1` (gerçek ekran gerektiren testler de çalışır) ya da bir önizleme klasörü
/// (`TEST_RUNNER_ADALMON_PREVIEW_DIR` / `..._PANEL_PREVIEW_DIR`; `screencapture -l` gerçek pencere ister).
@objc(AdalmonTestEnvironment)
final class AdalmonTestEnvironment: NSObject {
    override init() {
        super.init()
        WindowGuard.installIfNeeded()
    }
}

enum ScreenTests {
    /// Gerçek ekran / menü çubuğu gerektiren testlerin açık olup olmadığı.
    static var enabled: Bool { ProcessInfo.processInfo.environment["ADALMON_SCREEN_TESTS"] == "1" }

    /// Bu test gerçek menü çubuğu öğesi / ön plandaki pencere ister; ekranı kullandığı için yalnızca açıkça istenince çalışır.
    static func requireScreen(_ what: String = "gerçek menü çubuğu öğesi") throws {
        try XCTSkipUnless(enabled, "\(what) gerekir: TEST_RUNNER_ADALMON_SCREEN_TESTS=1 ile çalıştırın (ekranda pencere/öğe görünür)")
    }
}

enum WindowGuard {
    nonisolated(unsafe) private(set) static var active = false
    nonisolated(unsafe) private static var installed = false

    static func installIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        let wantsRealScreen = env["ADALMON_SCREEN_TESTS"] == "1" || env["ADALMON_PREVIEW_DIR"] != nil || env["ADALMON_PANEL_PREVIEW_DIR"] != nil
        guard !wantsRealScreen, !installed else { return }
        installed = true
        active = true
        swap(NSWindow.self, Selector(("orderWindow:relativeTo:")), #selector(NSWindow.guard_orderWindow(_:relativeTo:)))
        swap(NSWindow.self, #selector(NSWindow.orderFront(_:)), #selector(NSWindow.guard_orderFront(_:)))
        swap(NSWindow.self, #selector(NSWindow.makeKeyAndOrderFront(_:)), #selector(NSWindow.guard_makeKeyAndOrderFront(_:)))
        swap(NSWindow.self, #selector(NSWindow.orderFrontRegardless), #selector(NSWindow.guard_orderFrontRegardless))
        swap(NSWindow.self, Selector(("setIsVisible:")), #selector(NSWindow.guard_setIsVisible(_:)))
        swap(NSWindow.self, #selector(setter: NSWindow.alphaValue), #selector(NSWindow.guard_setAlphaValue(_:)))
        swap(NSWindow.self, #selector(getter: NSWindow.alphaValue), #selector(NSWindow.guard_alphaValue))
        // Uygulama etkinleştirmesi kullanıcının önündeki uygulamadan odağı çalar; testlerde gerekmez.
        swap(NSApplication.self, Selector(("activate")), #selector(NSApplication.guard_activate))
        swap(NSApplication.self, Selector(("activateIgnoringOtherApps:")), Selector(("guard_activateIgnoringOtherApps:")))
    }

    private static func swap(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let a = class_getInstanceMethod(cls, original), let b = class_getInstanceMethod(cls, replacement) else { return }
        method_exchangeImplementations(a, b)
    }
}

nonisolated(unsafe) private var logicalAlphaKey: UInt8 = 0

extension NSWindow {
    /// Pencere sunucusu için alfa 0; mantıksal alfa (testlerin/üretim kodunun okuduğu) ayrı tutulur.
    fileprivate func guard_hide(force: Bool = false) {
        guard WindowGuard.active else { return }
        animationBehavior = .none // açılış animasyonu sonunda alfayı 1'e çekmesin
        if objc_getAssociatedObject(self, &logicalAlphaKey) == nil {
            objc_setAssociatedObject(self, &logicalAlphaKey, NSNumber(value: Double(guard_alphaValue())), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        guard_setAlphaValue(0)
    }

    @objc fileprivate func guard_orderWindow(_ place: NSWindow.OrderingMode, relativeTo other: Int) {
        if place != .out { guard_hide() }
        guard_orderWindow(place, relativeTo: other)
        if place != .out { guard_hide(force: true) }
    }
    @objc fileprivate func guard_orderFront(_ sender: Any?) { guard_hide(); guard_orderFront(sender); guard_hide(force: true) }
    @objc fileprivate func guard_makeKeyAndOrderFront(_ sender: Any?) { guard_hide(); guard_makeKeyAndOrderFront(sender); guard_hide(force: true) }
    @objc fileprivate func guard_orderFrontRegardless() { guard_hide(); guard_orderFrontRegardless(); guard_hide(force: true) }
    @objc fileprivate func guard_setIsVisible(_ visible: Bool) { if visible { guard_hide() }; guard_setIsVisible(visible); if visible { guard_hide(force: true) } }

    @objc fileprivate func guard_setAlphaValue(_ value: CGFloat) {
        if WindowGuard.active {
            objc_setAssociatedObject(self, &logicalAlphaKey, NSNumber(value: Double(value)), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            guard_setAlphaValue(0)
        } else {
            guard_setAlphaValue(value)
        }
    }
    @objc fileprivate func guard_alphaValue() -> CGFloat {
        if WindowGuard.active, let logical = objc_getAssociatedObject(self, &logicalAlphaKey) as? NSNumber { return CGFloat(logical.doubleValue) }
        return guard_alphaValue()
    }
}

extension NSApplication {
    @objc fileprivate func guard_activate() {}
    @objc(guard_activateIgnoringOtherApps:) fileprivate func guard_activateIgnoring(_ flag: Bool) {}
}

/// Koruma gerçekten kurulu mu ve gösterilen pencerenin pencere sunucusu alfası 0 mı (ekranda görünmez).
@MainActor
final class WindowGuardTests: XCTestCase {
    func testShownWindowIsInvisibleToWindowServerButLogicallyOpaque() throws {
        try XCTSkipIf(ScreenTests.enabled, "ekran testleri açık: koruma kapalı")
        XCTAssertTrue(WindowGuard.active, "NSPrincipalClass ile kurulmalı")
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.isVisible)
        // Pencere sunucusuna iletim bir çalıştırma döngüsü turu sonra yansır.
        XCTAssertEqual(window.alphaValue, 1, "mantıksal alfa korunur")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
        let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
            .first { ($0[kCGWindowNumber as String] as? Int) == window.windowNumber }
        XCTAssertEqual((info?[kCGWindowAlpha as String] as? Double) ?? -1, 0, accuracy: 0.001, "pencere sunucusunda şeffaf")
    }
}
