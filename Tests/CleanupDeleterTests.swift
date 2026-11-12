import XCTest
@testable import Adalmon

/// CleanupDeleter kapsamları ve ortak denetimler. Her şey geçici bir sahte ev klasöründe; gerçek Çöp Sepeti'ne hiçbir şey gitmez
/// (Çöp'e taşıma fixture içindeki FakeTrash'e yapılır), günlük fixture içindeki log.jsonl'e yazılır.
final class CleanupDeleterTests: XCTestCase {
    private var fixture: URL!
    private var home: String { fixture.path }
    private var fakeTrash: URL { fixture.appending(path: "FakeTrash", directoryHint: .isDirectory) }
    private var logURL: URL { fixture.appending(path: "log.jsonl") }

    /// Silme kapanışlarının kaç kez çağrıldığı (Sendable kapanışlardan yazılır).
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var _trash: [String] = []
        private var _remove: [String] = []
        var trash: [String] { lock.withLock { _trash } }
        var remove: [String] { lock.withLock { _remove } }
        func addTrash(_ p: String) { lock.withLock { _trash.append(p) } }
        func addRemove(_ p: String) { lock.withLock { _remove.append(p) } }
    }

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory.appending(path: "deleter-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fixture)
    }

    // MARK: Yardımcılar

    @discardableResult
    private func makeDir(_ rel: String) throws -> String {
        let url = fixture.appending(path: rel, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url.appending(path: "payload.bin"))
        return url.path
    }

    @discardableResult
    private func makeFile(_ rel: String, _ text: String = "data") throws -> String {
        let url = fixture.appending(path: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url.path
    }

    private func makeApp(_ rel: String, bundleID: String) throws -> String {
        let path = try makeDir(rel + "/Contents")
        let plist: NSDictionary = ["CFBundleIdentifier": bundleID]
        XCTAssertTrue(plist.write(toFile: path + "/Info.plist", atomically: true))
        return (path as NSString).deletingLastPathComponent
    }

    private func candidate(_ path: String, _ scope: DeletionScope, blocking: Set<String> = []) -> DeletionCandidate {
        var st = stat()
        let ok = lstat(path, &st) == 0
        return DeletionCandidate(path: path, dev: ok ? st.st_dev : 0, ino: ok ? st.st_ino : 0, bytes: 1, kind: "test.item",
                                 scope: scope, blockingBundleIDs: blocking, displayName: (path as NSString).lastPathComponent)
    }

    private func deleter(running: Set<String> = [], own: [String] = [], calls: Calls = Calls(),
                         realRemove: Bool = false, afterValidation: (@Sendable (DeletionCandidate) -> Void)? = nil) -> CleanupDeleter {
        let trashDir = fakeTrash
        return CleanupDeleter(
            home: home, runningBundleIDs: { running }, logURL: logURL, ownPaths: own,
            moveToTrash: { url in
                calls.addTrash(url.path)
                let dest = trashDir.appending(path: url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            removePermanently: realRemove ? CleanupDeleter.systemRemove : { @Sendable url in calls.addRemove(url.path) },
            afterValidation: afterValidation
        )
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    // MARK: .directChild

    func testDirectChildScope() throws {
        let root = try makeDir("Library/Caches")
        let child = try makeDir("Library/Caches/com.foo")
        let deep = try makeDir("Library/Caches/com.foo/sub")
        let skipped = try makeDir("Library/Caches/com.apple.x")
        let sibling = try makeDir("Library/Caches2/x")
        let outsideDir = fixture.deletingLastPathComponent().appending(path: "deleter-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outsideDir.appending(path: "x"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        let outsideRoot = outsideDir.appending(path: "x").path
        let scope = DeletionScope.directChild(roots: [DeletionRoot(path: root, names: NameRule(skipPrefixes: ["com.apple."]))])
        let d = deleter()
        XCTAssertNil(d.validate(candidate(child, scope)))
        XCTAssertEqual(d.validate(candidate(root, scope)), .isRoot)
        XCTAssertEqual(d.validate(candidate(deep, scope)), .notDirectChild)
        XCTAssertEqual(d.validate(candidate(skipped, scope)), .nameNotAllowed)
        XCTAssertEqual(d.validate(candidate(sibling, scope)), .notUnderAllowedRoot)
        // Ev dışındaki kök kabul edilmez.
        let outScope = DeletionScope.directChild(roots: [DeletionRoot(path: (outsideRoot as NSString).deletingLastPathComponent)])
        XCTAssertEqual(d.validate(candidate(outsideRoot, outScope)), .notUnderAllowedRoot)
    }

    // MARK: .descendant

    func testDescendantScope() throws {
        let projects = try makeDir("Projects")
        let nm = try makeDir("Projects/app/web/node_modules")
        let src = try makeDir("Projects/app/src")
        let outside = try makeDir("Other/node_modules")
        let allow: Set<String> = ["node_modules", ".build"]
        let scope = DeletionScope.descendant(roots: [projects], nameAllowlist: allow)
        let d = deleter()
        XCTAssertNil(d.validate(candidate(nm, scope)))
        XCTAssertEqual(d.validate(candidate(src, scope)), .nameNotAllowed)
        XCTAssertEqual(d.validate(candidate(projects, scope)), .isRoot, "seçilen kökün kendisi silinmez")
        XCTAssertEqual(d.validate(candidate(outside, scope)), .notUnderAllowedRoot)
        // Ad listesi yoksa her alt öğe (büyük dosyalar gibi).
        let big = try makeFile("Projects/app/big.mov")
        XCTAssertNil(d.validate(candidate(big, .descendant(roots: [projects], nameAllowlist: nil))))
        // Ev kökü seçilebilir; korunan klasörler yine silinemez.
        let homeScope = DeletionScope.descendant(roots: [home], nameAllowlist: nil)
        XCTAssertNil(d.validate(candidate(big, homeScope)))
        let docs = try makeDir("Documents")
        XCTAssertEqual(d.validate(candidate(docs, homeScope)), .protectedPath)
        let prefs = try makeDir("Library/Preferences")
        XCTAssertEqual(d.validate(candidate(prefs, homeScope)), .protectedPath, "~/Library kök klasörleri korunur")
        let library = try makeDir("Library")
        XCTAssertEqual(d.validate(candidate(library, homeScope)), .protectedPath)
        // ~/Library kendisi kök olamaz; ev dışı (harici birim olmayan) kök olamaz.
        let libFile = try makeFile("Library/Logs/x/a.log")
        XCTAssertEqual(d.validate(candidate(libFile, .descendant(roots: [home + "/Library"], nameAllowlist: nil))), .rootNotAllowed)
        let foreign = fixture.deletingLastPathComponent().appending(path: "deleter-foreign-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: foreign.appending(path: "x"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: foreign) }
        XCTAssertEqual(d.validate(candidate(foreign.appending(path: "x").path, .descendant(roots: [foreign.path], nameAllowlist: nil))), .rootNotAllowed)
    }

    func testDescendantRootRules() {
        let homeParts = CleanupDeleter.components("/Users/u")
        let ok = ["/Users/u", "/Users/u/Projects", "/Volumes/Ext", "/Volumes/Ext/Work"]
        let bad = ["/", "/Users", "/Users/other", "/Users/u/Library", "/Volumes", "/System", "/Applications", "/private/var"]
        for p in ok { XCTAssertTrue(CleanupDeleter.isAllowedDescendantRoot(CleanupDeleter.components(p), homeParts: homeParts), p) }
        for p in bad { XCTAssertFalse(CleanupDeleter.isAllowedDescendantRoot(CleanupDeleter.components(p), homeParts: homeParts), p) }
        XCTAssertTrue(CleanupDeleter.isProtected(CleanupDeleter.components("/Volumes/Ext"), homeParts: homeParts), "birimin kendisi silinmez")
    }

    func testSymlinkInsideRootPointingOutsideIsRefused() throws {
        let projects = try makeDir("Projects")
        let secret = try makeDir("Secret/node_modules")
        XCTAssertEqual(symlink(fixture.appending(path: "Secret").path, projects + "/escape"), 0)
        let viaLink = projects + "/escape/node_modules"
        let d = deleter()
        let scope = DeletionScope.descendant(roots: [projects], nameAllowlist: ["node_modules"])
        XCTAssertEqual(d.validate(candidate(viaLink, scope)), .notUnderAllowedRoot, "üst yoldaki bağ çözülür")
        XCTAssertEqual(d.validate(candidate(projects + "/escape", .descendant(roots: [projects], nameAllowlist: nil))), .symlink)
        XCTAssertTrue(exists(secret))
    }

    // MARK: .appBundle

    func testAppBundleScope() throws {
        let foo = try makeApp("Applications/Foo.app", bundleID: "com.foo.Foo")
        let apple = try makeApp("Applications/Pages.app", bundleID: "com.apple.iWork.Pages")
        let nested = try makeApp("Applications/Sub/Bar.app", bundleID: "com.bar")
        let notApp = try makeDir("Applications/Folder")
        let fileApp = try makeFile("Applications/Fake.app")
        let d = deleter()
        XCTAssertNil(d.validate(candidate(foo, .appBundle)))
        XCTAssertEqual(d.validate(candidate(apple, .appBundle)), .appleApp)
        XCTAssertEqual(d.validate(candidate(nested, .appBundle)), .notUnderAllowedRoot, "~/Applications altında alt klasör yok")
        XCTAssertEqual(d.validate(candidate(notApp, .appBundle)), .notAppBundle)
        XCTAssertEqual(d.validate(candidate(fileApp, .appBundle)), .notAppBundle)
        XCTAssertEqual(d.validate(candidate(foo, .appBundle, blocking: ["com.foo.Foo"]), running: ["com.foo.Foo"]), .appRunning)
    }

    func testAppBundleParentShapes() {
        let homeParts = CleanupDeleter.components("/Users/u")
        func ok(_ parent: String) -> Bool { CleanupDeleter.isAllowedAppParent(CleanupDeleter.components(parent), homeParts: homeParts) }
        XCTAssertTrue(ok("/Applications"))
        XCTAssertTrue(ok("/Applications/Utilities"))
        XCTAssertTrue(ok("/Users/u/Applications"))
        XCTAssertFalse(ok("/System/Applications"))
        XCTAssertFalse(ok("/Applications/A/B"))
        XCTAssertFalse(ok("/Applications/Xcode.app"), "paket içindeki paket değil")
        XCTAssertFalse(ok("/Users/u/Applications/Sub"))
        XCTAssertFalse(ok("/Users/u"))
        XCTAssertTrue(CleanupDeleter.isUnderSystemTree(CleanupDeleter.components("/System/Applications/Mail.app")))
    }

    // MARK: .exactFile

    func testExactFileScope() throws {
        let history = try makeFile("Library/Browser/History")
        let other = try makeFile("Library/Browser/Bookmarks")
        let dir = try makeDir("Library/Browser/Folder")
        let scope = DeletionScope.exactFile(allowed: [history, dir])
        let d = deleter()
        XCTAssertNil(d.validate(candidate(history, scope)))
        XCTAssertEqual(d.validate(candidate(other, scope)), .notListedFile)
        XCTAssertEqual(d.validate(candidate(dir, scope)), .notRegularFile)
    }

    // MARK: Ortak denetimler

    func testOwnDataAndRunningAppAreRefused() throws {
        let projects = try makeDir("Projects")
        let own = try makeDir("Projects/AdalmonSupport")
        let inside = try makeDir("Projects/AdalmonSupport/cache")
        let scope = DeletionScope.descendant(roots: [projects], nameAllowlist: nil)
        let d = deleter(own: [own])
        XCTAssertEqual(d.validate(candidate(own, scope)), .ownData)
        XCTAssertEqual(d.validate(candidate(inside, scope)), .ownData)
        let parent = try makeDir("Projects/Parent")
        let d2 = deleter(own: [parent + "/Own"])
        XCTAssertEqual(d2.validate(candidate(parent, scope)), .ownData, "kendi verisinin atası da silinmez")

        let other = try makeDir("Projects/other")
        let calls = Calls()
        let results = deleter(running: ["com.x"], calls: calls).delete([candidate(other, scope, blocking: ["com.x"])], mode: .permanent)
        XCTAssertEqual(results.first?.outcome, .skipped(.appRunning))
        XCTAssertTrue(calls.remove.isEmpty)
        XCTAssertTrue(exists(other))
    }

    func testRunningAppsAreReadAtDeleteTime() throws {
        let projects = try makeDir("Projects")
        let item = try makeDir("Projects/x")
        final class Counter: @unchecked Sendable { var n = 0 }
        let counter = Counter()
        let d = CleanupDeleter(home: home, runningBundleIDs: { counter.n += 1; return ["com.x"] }, logURL: logURL, ownPaths: [],
                               moveToTrash: { _ in nil }, removePermanently: { _ in })
        XCTAssertEqual(counter.n, 0)
        let r = d.delete([candidate(item, .descendant(roots: [projects], nameAllowlist: nil), blocking: ["com.x"])], mode: .trash)
        XCTAssertEqual(counter.n, 1)
        XCTAssertEqual(r.first?.outcome, .skipped(.appRunning))
    }

    // MARK: Tarama ile silme arasında değişen dosya

    func testSwappedBeforeDeleteIsRefusedInBothModes() throws {
        let projects = try makeDir("Projects")
        for mode in DeleteMode.allCases {
            let path = try makeDir("Projects/item-\(mode.rawValue)")
            let scanned = candidate(path, .descendant(roots: [projects], nameAllowlist: nil))
            try FileManager.default.moveItem(atPath: path, toPath: path + "-old")
            try makeDir("Projects/item-\(mode.rawValue)")
            let calls = Calls()
            let r = deleter(calls: calls).delete([scanned], mode: mode)
            XCTAssertEqual(r.first?.outcome, .skipped(.changed), mode.rawValue)
            XCTAssertTrue(calls.trash.isEmpty && calls.remove.isEmpty, mode.rawValue)
            XCTAssertTrue(exists(path + "/payload.bin"), mode.rawValue)
        }
    }

    func testSwappedAfterValidationIsCaughtBySecondCheck() throws {
        let projects = try makeDir("Projects")
        for mode in DeleteMode.allCases {
            let path = try makeDir("Projects/race-\(mode.rawValue)")
            let secret = try makeDir("Secret-\(mode.rawValue)")
            let scanned = candidate(path, .descendant(roots: [projects], nameAllowlist: nil))
            let calls = Calls()
            // Doğrulama geçtikten hemen sonra öğe bir bağla değiştirilir.
            let d = deleter(calls: calls, afterValidation: { c in
                try? FileManager.default.moveItem(atPath: c.path, toPath: c.path + "-moved")
                _ = symlink(secret, c.path)
            })
            let r = d.delete([scanned], mode: mode)
            XCTAssertEqual(r.first?.outcome, .skipped(.symlink), mode.rawValue)
            XCTAssertTrue(calls.trash.isEmpty && calls.remove.isEmpty, mode.rawValue)
            XCTAssertTrue(exists(secret + "/payload.bin"), mode.rawValue)

            let path2 = try makeDir("Projects/race2-\(mode.rawValue)")
            let d2 = deleter(calls: calls, afterValidation: { c in
                try? FileManager.default.moveItem(atPath: c.path, toPath: c.path + "-moved")
                try? FileManager.default.createDirectory(atPath: c.path, withIntermediateDirectories: false)
            })
            let r2 = d2.delete([candidate(path2, .descendant(roots: [projects], nameAllowlist: nil))], mode: mode)
            XCTAssertEqual(r2.first?.outcome, .skipped(.changed), mode.rawValue)
            XCTAssertTrue(calls.trash.isEmpty && calls.remove.isEmpty, mode.rawValue)
        }
    }

    // MARK: Kalıcı silme gerçekten siler (yalnızca fixture içinde)

    func testPermanentDeleteRemovesOnlyTheItemInsideFixture() throws {
        let projects = try makeDir("Projects")
        let target = try makeDir("Projects/app/node_modules")
        try makeFile("Projects/app/node_modules/pkg/index.js")
        let keep = try makeFile("Projects/app/package.json")
        let keepSibling = try makeDir("Projects/app/src")
        let calls = Calls()
        let d = deleter(calls: calls, realRemove: true)
        let r = d.delete([candidate(target, .descendant(roots: [projects], nameAllowlist: ["node_modules"]))], mode: .permanent)
        XCTAssertEqual(r.first?.outcome, .deleted)
        XCTAssertTrue(r.first?.isRemoved == true)
        XCTAssertFalse(exists(target))
        XCTAssertTrue(exists(keep))
        XCTAssertTrue(exists(keepSibling + "/payload.bin"))
        XCTAssertTrue(exists(projects + "/payload.bin"))
        XCTAssertTrue(calls.trash.isEmpty, "kalıcı silmede Çöp'e taşınmaz")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fakeTrash.path), [])

        let entry = try XCTUnwrap(CleanupAuditLog.read(url: logURL).first)
        XCTAssertEqual(entry.mode, .permanent)
        XCTAssertEqual(entry.result, "deleted")
        XCTAssertEqual(entry.kind, "test.item")
        XCTAssertNil(entry.trashedTo)
        XCTAssertTrue(entry.isDone)
    }

    func testTrashModeUsesTrashOnly() throws {
        let projects = try makeDir("Projects")
        let target = try makeDir("Projects/old")
        let calls = Calls()
        let r = deleter(calls: calls).delete([candidate(target, .descendant(roots: [projects], nameAllowlist: nil))], mode: .trash)
        XCTAssertEqual(r.first?.outcome, .trashed(to: fakeTrash.appending(path: "old")))
        XCTAssertEqual(calls.trash.count, 1)
        XCTAssertTrue(calls.remove.isEmpty)
        let entry = try XCTUnwrap(CleanupAuditLog.read(url: logURL).first)
        XCTAssertEqual(entry.mode, .trash)
        XCTAssertEqual(entry.result, "moved")
    }

    // MARK: Günlük

    func testOldLogLineWithoutModeReadsAsTrash() throws {
        let old = #"{"bytes":2097152,"category":"appCaches","date":"2026-11-01T10:00:00Z","path":"/Users/u/Library/Caches/com.foo","result":"moved","trashedTo":"/Users/u/.Trash/com.foo"}"#
        try Data((old + "\n").utf8).write(to: logURL)
        let projects = try makeDir("Projects")
        let target = try makeDir("Projects/x")
        _ = deleter(realRemove: true).delete([candidate(target, .descendant(roots: [projects], nameAllowlist: nil))], mode: .permanent)
        let entries = CleanupAuditLog.read(url: logURL)
        XCTAssertEqual(entries.count, 2)
        let oldEntry = try XCTUnwrap(entries.last)
        XCTAssertEqual(oldEntry.mode, .trash)
        XCTAssertEqual(oldEntry.kind, "appCaches")
        XCTAssertEqual(oldEntry.trashedTo, "/Users/u/.Trash/com.foo")
        XCTAssertEqual(entries.first?.mode, .permanent)
    }

    func testLogCapKeepsNewestLines() throws {
        let lines = (0..<CleanupAuditLog.limit).map { #"{"path":"/old/\#($0)","result":"moved"}"# }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: logURL)
        _ = deleter().delete([candidate("/nonexistent-deleter-test/new", .appBundle)], mode: .permanent)
        let text = try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(text.count, CleanupAuditLog.limit)
        XCTAssertTrue(text.last?.contains("\"mode\":\"permanent\"") == true)
        XCTAssertFalse(text.contains { $0.contains("\"/old/0\"") })
    }

    // MARK: CLEAN-01 köprüsü

    func testLegacyItemBecomesDirectChildCandidate() {
        let roots = CleanupCatalog.roots(home: "/Users/u", ownBundleID: nil)
        let item = CleanupItem(path: "/Users/u/Library/Caches/com.foo", rootPath: "/Users/u/Library/Caches", category: .appCaches,
                               bytes: 5, isDirectory: true, modified: nil, dev: 1, ino: 2, blockedReason: nil)
        let c = DeletionCandidate(item: item, roots: roots)
        XCTAssertEqual(c.kind, "junk.appCaches")
        XCTAssertEqual(c.blockingBundleIDs, ["com.foo"])
        guard case .directChild(let r) = c.scope else { return XCTFail("kapsam") }
        XCTAssertEqual(r.map(\.path), ["/Users/u/Library/Caches"])
        let trash = CleanupItem(path: "/Users/u/.Trash/x", rootPath: "/Users/u/.Trash", category: .trash,
                                bytes: 1, isDirectory: true, modified: nil, dev: 1, ino: 2, blockedReason: nil)
        XCTAssertEqual(DeletionCandidate(item: trash, roots: roots).scope, .directChild(roots: []))
    }

    // MARK: Onay akışı

    func testConfirmationFlow() {
        var trash = DeleteConfirmationFlow(mode: .trash)
        XCTAssertTrue(trash.canConfirm)
        XCTAssertTrue(trash.primaryPressed())

        var permanent = DeleteConfirmationFlow(mode: .permanent)
        XCTAssertFalse(permanent.canConfirm)
        XCTAssertFalse(permanent.primaryPressed(), "ilk onay yalnızca ikinci adıma geçirir")
        XCTAssertEqual(permanent.step, .permanentConfirm)
        XCTAssertFalse(permanent.canConfirm, "kutu işaretlenmeden silinmez")
        XCTAssertFalse(permanent.primaryPressed())
        permanent.acknowledged = true
        XCTAssertTrue(permanent.canConfirm)
        XCTAssertTrue(permanent.primaryPressed())

        let s = DeleteSummary(count: 3, bytes: 3 << 20, mode: .permanent)
        XCTAssertTrue(s.undoNote.hasPrefix("GERİ ALINAMAZ"))
        XCTAssertEqual(DeleteSummary(count: 1, bytes: 1, mode: .trash).undoNote, "Çöp Sepeti'nden geri alınabilir.")
    }
}
