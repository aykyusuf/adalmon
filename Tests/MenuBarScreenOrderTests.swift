import XCTest
@testable import Adalmon

@MainActor
final class MenuBarScreenOrderTests: XCTestCase {
    private func comps(_ fields: [DataField]) -> [MenuBarComponent] { fields.map { MenuBarComponent($0) } }

    func testReordersToScreenOrder() {
        let c = comps([.cpu, .memoryUsed, .download])
        let out = MenuBarConfig.reordered(c, screenOrder: [c[2].id, c[0].id, c[1].id])
        XCTAssertEqual(out.map(\.id), [c[2].id, c[0].id, c[1].id])
    }

    func testMissingIdsGoToEndInOriginalOrder() {
        let c = comps([.cpu, .memoryUsed, .download, .upload])
        let out = MenuBarConfig.reordered(c, screenOrder: [c[3].id, c[1].id, UUID()])
        XCTAssertEqual(out.map(\.id), [c[3].id, c[1].id, c[0].id, c[2].id])
    }

    func testDuplicateScreenIdsIgnored() {
        let c = comps([.cpu, .memoryUsed])
        let out = MenuBarConfig.reordered(c, screenOrder: [c[1].id, c[1].id, c[0].id])
        XCTAssertEqual(out.map(\.id), [c[1].id, c[0].id])
    }

    func testDisabledComponentsKeepTheirSlot() {
        var c = comps([.cpu, .memoryUsed, .download, .upload])
        c[1].enabled = false
        let out = MenuBarConfig.reordered(c, screenOrder: [c[3].id, c[2].id, c[0].id])
        XCTAssertEqual(out.map(\.id), [c[3].id, c[1].id, c[2].id, c[0].id])
        XCTAssertFalse(out[1].enabled)
    }

    func testPinnedDeviceComponentsReorderLikeOthers() {
        var c = comps([.cpu, .memoryUsed])
        c.append(.device("phone-1", name: "iPhone"))
        let out = MenuBarConfig.reordered(c, screenOrder: [c[2].id, c[0].id, c[1].id])
        XCTAssertEqual(out.map(\.id), [c[2].id, c[0].id, c[1].id])
        XCTAssertEqual(out[0].deviceID, "phone-1")
    }

    func testSyncedFromScreenSortsByXAndBreaksTiesByCurrentOrder() {
        let c = comps([.cpu, .memoryUsed, .download, .upload])
        let config = MenuBarConfig(components: c, displayMode: .separate)
        let out = config.syncedFromScreen(positions: [c[0].id: 300, c[1].id: 100, c[2].id: 100, c[3].id: 50, UUID(): 1])
        XCTAssertEqual(out.components.map(\.id), [c[3].id, c[1].id, c[2].id, c[0].id])
    }

    func testStoreSyncUnchangedAppliedAndEmpty() {
        let suite = "adalmon.tests.screenorder"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "screenorder-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let store = MenuBarConfigStore(defaults: defaults, archive: MenuBarLayoutArchive(fileURL: file))
        let c = store.config.components
        XCTAssertGreaterThan(c.count, 1)
        XCTAssertEqual(store.syncOrder(positions: [:]), .noItems)
        let same = Dictionary(uniqueKeysWithValues: c.enumerated().map { ($1.id, CGFloat($0) * 10) })
        XCTAssertEqual(store.syncOrder(positions: same), .unchanged)
        XCTAssertNil(store.undo)
        let reversed = Dictionary(uniqueKeysWithValues: c.enumerated().map { ($1.id, CGFloat(c.count - $0) * 10) })
        XCTAssertEqual(store.syncOrder(positions: reversed), .applied)
        XCTAssertEqual(store.config.enabledComponents.map(\.id), c.filter(\.enabled).reversed().map(\.id))
        XCTAssertNotNil(store.undo)
        store.undoLastReplace()
        XCTAssertEqual(store.config.components.map(\.id), c.map(\.id))
    }
}
