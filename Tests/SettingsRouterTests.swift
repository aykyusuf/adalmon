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

@MainActor
final class DockMobileSettingsRoutingTests: XCTestCase {
    func testDockSidebarOmitsMobileDataSettings() {
        XCTAssertFalse(MainSection.dockSettingsSections.contains(.mobileData))
        XCTAssertEqual(MainSection.dockSettingsSections.count, SettingsSection.allCases.count - 1)
        // Ayrı Ayarlar penceresi (Dock kapalı) hâlâ tüm bölümleri gösterir.
        XCTAssertTrue(SettingsSection.allCases.contains(.mobileData))
    }

    func testOpenMobileDataInDockModeShowsMobilePage() {
        let router = SettingsRouter(isDockModeOn: { true })
        var shown = 0
        router.attach(showMainWindow: { shown += 1 }, showSettingsWindow: {})
        router.open(.mobileData)
        XCTAssertEqual(router.selectedMainSection, .mobile)
        XCTAssertEqual(shown, 1)
    }

    func testOpenWithLastUsedMobileSectionInDockModeShowsMobilePage() {
        let router = SettingsRouter(isDockModeOn: { true })
        router.attach(showMainWindow: {}, showSettingsWindow: {})
        router.selectedSettingsSection = .mobileData
        router.open()
        XCTAssertEqual(router.selectedMainSection, .mobile)
    }

    func testOpenMobileDataWithoutDockUsesSettingsWindow() {
        let router = SettingsRouter(isDockModeOn: { false })
        var settings = 0
        router.attach(showMainWindow: {}, showSettingsWindow: { settings += 1 })
        router.open(.mobileData)
        XCTAssertEqual(router.selectedSettingsSection, .mobileData)
        XCTAssertEqual(router.selectedMainSection, .overview)
        XCTAssertEqual(settings, 1)
    }

    func testSavedMobileSettingsSelectionMapsToMobilePage() {
        XCTAssertEqual(MainSection.settings(.mobileData).dockCanonical, .mobile)
        XCTAssertEqual(MainSection.settings(.filter).dockCanonical, .settings(.filter))
    }
}
