import XCTest
@testable import Adalmon

@MainActor
final class SettingsRouterTests: XCTestCase {
    private func makeRouter(dock: Bool, calls: Box) -> SettingsRouter {
        let router = SettingsRouter(isDockModeOn: { dock })
        router.attach(showMainWindow: { calls.main += 1 }, showSettingsWindow: { calls.settings += 1 })
        return router
    }

    private final class Box {
        var main = 0
        var settings = 0
    }

    func testDockOnOpensMainWindowAtRequestedSection() {
        let calls = Box()
        let router = makeRouter(dock: true, calls: calls)
        router.open(.panel)
        XCTAssertEqual(router.selectedMainSection, .settings(.panel))
        XCTAssertEqual(calls.main, 1)
        XCTAssertEqual(calls.settings, 0)
    }

    func testDockOffOpensSettingsWindow() {
        let calls = Box()
        let router = makeRouter(dock: false, calls: calls)
        router.open(.throttle)
        XCTAssertEqual(router.selectedSettingsSection, .throttle)
        XCTAssertEqual(router.selectedMainSection, .overview)
        XCTAssertEqual(calls.main, 0)
        XCTAssertEqual(calls.settings, 1)
    }

    func testDefaultsToGeneralThenLastUsed() {
        let calls = Box()
        let router = makeRouter(dock: true, calls: calls)
        router.open()
        XCTAssertEqual(router.selectedMainSection, .settings(.general))
        router.selectedMainSection = .settings(.filter)
        router.selectedMainSection = .network
        router.open()
        XCTAssertEqual(router.selectedMainSection, .settings(.filter))
        XCTAssertEqual(calls.main, 2)
    }

    func testSidebarEntriesCoverPagesAndEverySettingsSection() {
        XCTAssertEqual(MainSection.allCases.count, MainSection.pages.count + SettingsSection.allCases.count)
        XCTAssertEqual(Set(MainSection.allCases.map(\.id)).count, MainSection.allCases.count)
    }
}
