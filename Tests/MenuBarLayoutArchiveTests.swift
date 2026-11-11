import XCTest
@testable import Adalmon

/// MENUBAR-02 / MENUBAR-03: kayıtlı düzenler, otomatik yedek, dışa/içe aktarma, geri al.
@MainActor
final class MenuBarLayoutArchiveTests: XCTestCase {
    private var dir: URL!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "menubar-archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var fileURL: URL { dir.appending(path: MenuBarLayoutArchive.fileName) }

    private func makeArchive() -> MenuBarLayoutArchive {
        MenuBarLayoutArchive(fileURL: fileURL, now: { [unowned self] in clock })
    }

    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "adalmon.tests.archive.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return d
    }

    /// Sabit (her erişimde yeni bileşen kimliği üretmesin diye bir kez kurulur).
    private lazy var customConfig: MenuBarConfig = {
        var c = MenuBarPreset.renkli.makeConfig()
        c.components[0].thresholds = Thresholds(warning: 0.35, critical: 0.9)
        c.spacing = 9
        return c
    }()

    func testSaveAndReloadFromDisk() {
        let archive = makeArchive()
        archive.save(customConfig, name: "  Çalışma  ")
        let reloaded = makeArchive()
        XCTAssertEqual(reloaded.saved.map(\.name), ["Çalışma"])
        XCTAssertEqual(reloaded.saved.first?.config, customConfig)
    }

    func testSavingSameNameOverwritesAndBacksUpOldVersion() {
        let archive = makeArchive()
        archive.save(customConfig, name: "A")
        archive.save(.default, name: "A")
        XCTAssertEqual(archive.saved.count, 1)
        XCTAssertEqual(archive.saved.first?.config, .default)
        XCTAssertEqual(archive.automatic.first?.config, customConfig, "üzerine yazılan sürüm otomatik yedekte kalmalı")
    }

    func testAutoBackupSkipsDuplicatesAndKeepsLimit() {
        let archive = makeArchive()
        archive.autoBackup(customConfig, reason: "x")
        archive.autoBackup(customConfig, reason: "x")
        XCTAssertEqual(archive.automatic.count, 1)
        for i in 0..<(MenuBarLayoutArchive.maxAutomatic + 5) {
            clock += 1
            var c = MenuBarConfig.default
            c.spacing = Double(i % 2 == 0 ? 3 : 7)
            c.labelOpacity = 0.6 + Double(i) / 1000
            archive.autoBackup(c, reason: "\(i)")
        }
        XCTAssertEqual(archive.automatic.count, MenuBarLayoutArchive.maxAutomatic)
        XCTAssertEqual(archive.automatic.first?.name, "\(MenuBarLayoutArchive.maxAutomatic + 4)", "en yenisi korunmalı")
    }

    func testStaleBackupOnlyAfterInterval() {
        let archive = makeArchive()
        archive.autoBackupIfStale(customConfig, interval: 3600, reason: "s")
        clock += 600
        archive.autoBackupIfStale(.default, interval: 3600, reason: "s")
        XCTAssertEqual(archive.automatic.count, 1)
        clock += 3600
        archive.autoBackupIfStale(.default, interval: 3600, reason: "s")
        XCTAssertEqual(archive.automatic.count, 2)
    }

    func testExportImportRoundTrip() throws {
        let archive = makeArchive()
        let entry = archive.save(customConfig, name: "Paylaşılan")
        let data = try MenuBarLayoutArchive.exportData(entry)
        let other = MenuBarLayoutArchive(fileURL: dir.appending(path: "other.json"))
        let imported = try other.importLayout(data)
        XCTAssertEqual(imported.config, customConfig)
        XCTAssertEqual(imported.name, "Paylaşılan")
        // Aynı adla ikinci içe aktarma ezmez.
        let second = try other.importLayout(data)
        XCTAssertNotEqual(second.name, imported.name)
        XCTAssertEqual(other.saved.count, 2)
    }

    func testImportRejectsForeignJSON() {
        let archive = makeArchive()
        XCTAssertThrowsError(try archive.importLayout(Data(#"{"hello":1}"#.utf8)))
        XCTAssertTrue(archive.entries.isEmpty)
    }

    func testUnreadableArchiveFileIsMovedAsideNotOverwritten() throws {
        try Data("bozuk".utf8).write(to: fileURL)
        let archive = makeArchive()
        XCTAssertTrue(archive.entries.isEmpty)
        archive.save(.default, name: "yeni")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.contains("unreadable") }, "\(files)")
    }

    // MARK: Store: yedek + geri al

    func testResetToDefaultBacksUpAndCanBeUndone() {
        let store = MenuBarConfigStore(defaults: makeDefaults(), archive: makeArchive())
        store.config = customConfig
        store.resetToDefault()
        XCTAssertEqual(store.config, .default)
        XCTAssertEqual(store.archive.automatic.first?.config, customConfig, "sıfırlamadan önce yedek alınmalı")
        XCTAssertEqual(store.undo?.previous, customConfig)
        store.undoLastReplace()
        XCTAssertEqual(store.config, customConfig)
        XCTAssertNil(store.undo)
    }

    func testPresetAndRestoreGoThroughBackup() {
        let store = MenuBarConfigStore(defaults: makeDefaults(), archive: makeArchive())
        store.config = customConfig
        let saved = store.saveCurrentLayout(name: "Benim")
        store.apply(.minimal)
        XCTAssertEqual(store.currentPreset, .minimal)
        XCTAssertEqual(store.config.spacing, customConfig.spacing, "hazır düzen gösterim ayarlarını korur")
        XCTAssertNotNil(store.undo)
        store.restore(saved)
        XCTAssertEqual(store.config, customConfig)
        XCTAssertTrue(store.archive.automatic.contains { MenuBarPreset.minimal.matches($0.config.components) }, "geri yüklemeden önce hazır düzen yedeklenmeli")
    }

    func testNoOpReplaceDoesNotCreateUndo() {
        let store = MenuBarConfigStore(defaults: makeDefaults(), archive: makeArchive())
        store.resetToDefault()
        XCTAssertNil(store.undo)
    }

    func testLaunchTakesBackup() {
        let d = makeDefaults()
        let archive = makeArchive()
        _ = MenuBarConfigStore(defaults: d, archive: archive)
        XCTAssertEqual(archive.automatic.count, 1)
    }

    func testFlippingPresetsNeverDropsOriginalDesign() {
        let store = MenuBarConfigStore(defaults: makeDefaults(), archive: makeArchive())
        store.config = customConfig
        for i in 0..<(MenuBarLayoutArchive.maxAutomatic * 2) {
            clock += 1
            store.apply(i % 2 == 0 ? .minimal : .grafik)
        }
        XCTAssertTrue(store.archive.automatic.contains { $0.config.isSameLayout(as: customConfig) }, "özgün tasarım yedeklerde kalmalı")
        XCTAssertLessThanOrEqual(store.archive.automatic.count, 4)
    }

    func testManualEditAfterReplaceClearsUndo() {
        let store = MenuBarConfigStore(defaults: makeDefaults(), archive: makeArchive())
        store.config = customConfig
        store.resetToDefault()
        XCTAssertNotNil(store.undo)
        store.config.spacing = 4
        XCTAssertNil(store.undo, "elle düzenlemeden sonra geri al eski hâle sessizce dönmemeli")
    }
}
