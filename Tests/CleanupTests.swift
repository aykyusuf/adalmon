import XCTest
@testable import Adalmon

/// Tüm testler geçici bir sahte ev klasöründe çalışır; gerçek ev klasörlerine (İndirilenler, .Trash, MobileSync, Caches) dokunmaz.
/// Silme (CleanupDeleter, .trash), fixture içindeki FakeTrash'e yapan sahte kapanışla; günlük fixture içindeki log.jsonl'e yazılır.
final class CleanupTests: XCTestCase {
    private var fixture: URL!
    private var home: String { fixture.path }
    private var fakeTrash: URL { fixture.appending(path: "FakeTrash", directoryHint: .isDirectory) }
    private var logURL: URL { fixture.appending(path: "log.jsonl") }
    private let mb = 1_048_576

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory.appending(path: "cleanup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // chmod 000 bırakılmış olabilir: silmeden önce geri aç.
        chmod(fixture.appending(path: "Library/Caches").path, 0o755)
        try? FileManager.default.removeItem(at: fixture)
    }

    // MARK: Yardımcılar

    @discardableResult
    private func write(_ rel: String, bytes: Int) throws -> URL {
        let url = fixture.appending(path: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 4096) { data[i] = UInt8(truncatingIfNeeded: i / 4096 + 1) } // seyrek dosya olmasın
        try data.write(to: url)
        return url
    }

    private func scan(_ categories: [CleanupCategory] = CleanupCategory.defaultScan, running: Set<String> = [],
                      now: Date = Date(), isCancelled: @escaping () -> Bool = { false }) -> CleanupScanner.Output {
        CleanupScanner.scan(categories: categories, home: home, runningBundleIDs: running, ownBundleID: nil, now: now, isCancelled: isCancelled)
    }

    private var roots: [CleanupRoot] { CleanupCatalog.roots(home: home, ownBundleID: nil) }

    private func trasher(running: Set<String> = []) -> CleanupDeleter {
        let trashDir = fakeTrash
        return CleanupDeleter(
            home: home, runningBundleIDs: { running }, logURL: logURL, ownPaths: [],
            moveToTrash: { url in
                let dest = trashDir.appending(path: url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            removePermanently: { _ in throw CocoaError(.featureUnsupported) }
        )
    }

    private func candidates(_ items: [CleanupItem]) -> [DeletionCandidate] {
        items.map { DeletionCandidate(item: $0, roots: roots) }
    }

    /// Taranmadan elle hazırlanmış öğe (dev/ino gerçek dosyadan; yoksa 0).
    private func item(_ path: String, _ category: CleanupCategory, bytes: UInt64 = 2 << 20) -> DeletionCandidate {
        DeletionCandidate(item: rawItem(path, category, bytes: bytes), roots: roots)
    }

    private func rawItem(_ path: String, _ category: CleanupCategory, bytes: UInt64 = 2 << 20) -> CleanupItem {
        var st = stat()
        let ok = lstat(path, &st) == 0
        return CleanupItem(
            path: path, rootPath: (path as NSString).deletingLastPathComponent, category: category, bytes: bytes,
            isDirectory: true, modified: nil, dev: ok ? st.st_dev : 0, ino: ok ? st.st_ino : 0, blockedReason: nil
        )
    }

    private func fakeTrashNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: fakeTrash.path)) ?? []).sorted()
    }

    private func logLines() -> [String] {
        ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    // MARK: Katalog ve tarama

    func testCatalogRootsAreUnderHomeAndDeduped() {
        let roots = CleanupCatalog.roots(home: home, ownBundleID: "com.adalmon.test")
        XCTAssertFalse(roots.isEmpty)
        for root in roots { XCTAssertTrue(root.path.hasPrefix(home + "/"), root.path) }
        XCTAssertEqual(Set(roots.map(\.path)).count, roots.count, "bir yol iki kategorinin kökü olamaz")
        let app = roots.first { $0.category == .appCaches }
        XCTAssertNotNil(app)
        for name in ["Homebrew", "pip", "Yarn", "pnpm", "com.adalmon.test"] { XCTAssertEqual(app?.allows(name), false, name) }
        XCTAssertEqual(app?.allows("com.apple.Foo"), false)
        XCTAssertEqual(app?.allows("com.foo"), true)
        XCTAssertFalse(roots.contains { $0.path.contains("CoreSimulator/Devices") })
        XCTAssertFalse(roots.contains { $0.category == .trash })
    }

    func testScanListsDirectChildrenWithSizes() throws {
        try write("Library/Caches/com.foo/a.bin", bytes: 3 * mb)
        try write("Library/Caches/com.small/s.bin", bytes: 100_000)
        try write("Library/Developer/Xcode/DerivedData/Proj-abc/b.bin", bytes: 2 * mb)
        try write("Library/Caches/Homebrew/dl.bin", bytes: 2 * mb)
        let out = scan()
        let byPath = Dictionary(uniqueKeysWithValues: out.items.map { ($0.path, $0) })
        let foo = try XCTUnwrap(byPath[home + "/Library/Caches/com.foo"])
        XCTAssertEqual(foo.category, .appCaches)
        XCTAssertGreaterThanOrEqual(foo.bytes, UInt64(3 * mb))
        XCTAssertTrue(foo.isDirectory)
        let proj = try XCTUnwrap(byPath[home + "/Library/Developer/Xcode/DerivedData/Proj-abc"])
        XCTAssertEqual(proj.category, .derivedData)
        XCTAssertGreaterThanOrEqual(proj.bytes, UInt64(2 * mb))
        XCTAssertNil(byPath[home + "/Library/Caches/com.small"], "1 MB altı listelenmez")
        XCTAssertNil(byPath[home + "/Library/Caches/Homebrew"], "Homebrew appCaches'e girmez")
        XCTAssertEqual(byPath[home + "/Library/Caches/Homebrew/dl.bin"]?.category, .pkgCaches)
        let rootPaths = Set(CleanupCatalog.roots(home: home).map(\.path))
        XCTAssertTrue(out.items.allSatisfy { !rootPaths.contains($0.path) }, "kök kendisi satır olmaz")
        XCTAssertEqual(out.states[home + "/Library/Caches"], .scanned)
    }

    func testScanSkipsSymlinkChildren() throws {
        try write("Outside/big.bin", bytes: 5 * mb)
        try write("Library/Caches/com.real/r.bin", bytes: 2 * mb)
        try FileManager.default.createDirectory(at: fixture.appending(path: "Library/Caches"), withIntermediateDirectories: true)
        XCTAssertEqual(symlink(fixture.appending(path: "Outside").path, fixture.appending(path: "Library/Caches/com.link").path), 0)
        let out = scan([.appCaches])
        XCTAssertNil(out.items.first { $0.path.hasSuffix("/com.link") })
        XCTAssertEqual(out.items.map(\.path), [home + "/Library/Caches/com.real"])
        XCTAssertLessThan(out.items.reduce(0) { $0 + $1.bytes }, UInt64(5 * mb), "bağın hedefi sayılmaz")
    }

    func testScanSkipsAppleAndProtectedCacheNames() throws {
        try write("Library/Caches/com.apple.Safari/x.bin", bytes: 2 * mb)
        try write("Library/Caches/CloudKit/x.bin", bytes: 2 * mb)
        try write("Library/Caches/com.foo/x.bin", bytes: 2 * mb)
        let names = scan([.appCaches]).items.map(\.name)
        XCTAssertEqual(names, ["com.foo"])
    }

    func testDefaultScanDoesNotIncludeExplicitCategories() throws {
        try write("Downloads/big.bin", bytes: 2 * mb)
        try write("Library/Application Support/MobileSync/Backup/dev1/b.bin", bytes: 2 * mb)
        try write("Library/Caches/com.foo/x.bin", bytes: 2 * mb)
        let out = scan()
        XCTAssertFalse(out.items.contains { $0.category == .downloads || $0.category == .iosBackups || $0.category == .trash })
        XCTAssertNil(out.states[home + "/Downloads"])
        XCTAssertNil(out.states[home + "/Library/Application Support/MobileSync/Backup"])
        XCTAssertFalse(out.items.isEmpty)
        // Pozitif kontrol: açıkça istenince listelenir (2 MB dosya, 200 gün sonrası "eski" sayılır).
        let later = Date().addingTimeInterval(200 * 86_400)
        let dl = scan([.downloads], now: later)
        XCTAssertEqual(dl.items.map(\.path), [home + "/Downloads/big.bin"])
        XCTAssertFalse(dl.items[0].isDirectory)
        let fresh = scan([.downloads])
        XCTAssertTrue(fresh.items.isEmpty, "küçük ve yeni dosya listelenmez")
    }

    func testDefaultSelection() throws {
        for c in [CleanupCategory.archives, .deviceSupport, .iosBackups, .downloads, .trash] { XCTAssertFalse(c.defaultSelected, c.rawValue) }
        for c in [CleanupCategory.appCaches, .derivedData, .simCaches, .pkgCaches] { XCTAssertTrue(c.defaultSelected, c.rawValue) }
        XCTAssertFalse(CleanupCategory.defaultScan.contains(.downloads))
        try write("Library/Caches/com.run/x.bin", bytes: 2 * mb)
        try write("Library/Caches/com.idle/x.bin", bytes: 2 * mb)
        try write("Library/Developer/Xcode/DerivedData/P/x.bin", bytes: 2 * mb)
        let out = scan(running: ["com.run", CleanupCatalog.xcodeBundleID])
        let byName = Dictionary(uniqueKeysWithValues: out.items.map { ($0.name, $0) })
        XCTAssertEqual(byName["com.run"]?.blockedReason, CleanupCatalog.runningBadge)
        XCTAssertNil(byName["com.idle"]?.blockedReason)
        XCTAssertEqual(byName["P"]?.blockedReason, CleanupCatalog.runningBadge, "Xcode açıkken DerivedData engelli")
    }

    func testScanCancellation() throws {
        for i in 0..<5 { try write("Library/Caches/com.f\(i)/x.bin", bytes: 2 * mb) }
        try write("Library/Developer/Xcode/DerivedData/P/x.bin", bytes: 2 * mb)
        var calls = 0
        let out = scan(isCancelled: { calls += 1; return calls > 1 })
        XCTAssertGreaterThan(calls, 0)
        XCTAssertLessThan(out.items.count, 6, "iptalden sonra tarama kesilir")
        XCTAssertFalse(out.items.contains { $0.category == .derivedData })
    }

    func testRootStates() throws {
        try write("Library/Caches/com.foo/x.bin", bytes: 2 * mb)
        let caches = fixture.appending(path: "Library/Caches").path
        let missingRoot = home + "/Library/Developer/Xcode/DerivedData"
        XCTAssertEqual(scan([.derivedData]).states[missingRoot], .missing)

        XCTAssertEqual(chmod(caches, 0o000), 0)
        defer { chmod(caches, 0o755) }
        let out = scan([.appCaches])
        XCTAssertEqual(out.states[caches], .noAccess)
        XCTAssertTrue(out.items.isEmpty)
    }

    // MARK: Doğrulama

    func testValidateRefusesRootItself() throws {
        try write("Library/Caches/com.foo/x.bin", bytes: 2 * mb)
        XCTAssertEqual(trasher().validate(item(home + "/Library/Caches", .appCaches)), .isRoot)
    }

    func testValidateRefusesDeeperThanDirectChild() throws {
        try write("Library/Caches/com.foo/sub/x.bin", bytes: 2 * mb)
        XCTAssertEqual(trasher().validate(item(home + "/Library/Caches/com.foo/sub", .appCaches)), .notDirectChild)
    }

    func testValidateRefusesSiblingPrefix() throws {
        try write("Library/Caches2/x/x.bin", bytes: 2 * mb)
        XCTAssertEqual(trasher().validate(item(home + "/Library/Caches2/x", .appCaches)), .notUnderAllowedRoot)
    }

    func testValidateRefusesDotDot() throws {
        try write("Library/Caches/com.foo/x.bin", bytes: 2 * mb)
        try write("Library/Preferences/x/x.bin", bytes: 2 * mb)
        let r = trasher().validate(item(home + "/Library/Caches/../Preferences/x", .appCaches))
        XCTAssertTrue(r == .notAbsolute || r == .notUnderAllowedRoot, "\(String(describing: r))")
        XCTAssertEqual(trasher().validate(item("relative/path", .appCaches)), .notAbsolute)
        XCTAssertEqual(trasher().validate(item("", .appCaches)), .notAbsolute)
    }

    func testValidateRefusesSymlinkSwappedAfterScan() throws {
        try write("Library/Caches/com.foo/x.bin", bytes: 2 * mb)
        let secret = try write("Documents/secret/s.txt", bytes: 10)
        let scanned = try XCTUnwrap(scan([.appCaches]).items.first)
        let path = fixture.appending(path: "Library/Caches/com.foo")
        try FileManager.default.moveItem(at: path, to: fixture.appending(path: "moved-away"))
        XCTAssertEqual(symlink(fixture.appending(path: "Documents/secret").path, path.path), 0)

        let results = trasher().delete(candidates([scanned]), mode: .trash)
        XCTAssertEqual(results.first?.outcome, .skipped(.symlink))
        XCTAssertTrue(fakeTrashNames().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secret.path))
    }

    func testValidateRefusesReplacedItem() throws {
        try write("Library/Caches/com.foo/x.bin", bytes: 2 * mb)
        let scanned = try XCTUnwrap(scan([.appCaches]).items.first)
        let path = fixture.appending(path: "Library/Caches/com.foo")
        // Eski klasör yaşarken yenisini kur: inode farklı olmalı.
        try FileManager.default.moveItem(at: path, to: fixture.appending(path: "old-copy"))
        try write("Library/Caches/com.foo/y.bin", bytes: 2 * mb)
        XCTAssertEqual(trasher().validate(candidates([scanned])[0]), .changed)
        XCTAssertTrue(trasher().delete(candidates([scanned]), mode: .trash).allSatisfy { !$0.isRemoved })
        XCTAssertTrue(fakeTrashNames().isEmpty)
    }

    func testValidateRefusesProtectedPaths() throws {
        try write("Documents/d.txt", bytes: 10)
        try FileManager.default.createDirectory(at: fixture.appending(path: "Library"), withIntermediateDirectories: true)
        let t = trasher()
        for rel in ["", "/Library", "/Documents", "/Library/Caches"] {
            try? FileManager.default.createDirectory(at: fixture.appending(path: rel), withIntermediateDirectories: true)
            for category in [CleanupCategory.appCaches, .derivedData, .pkgCaches] {
                XCTAssertNotNil(t.validate(item(home + rel, category)), "\(rel) \(category)")
            }
        }
        let protected = CleanupDeleter.protectedPaths(homeParts: CleanupDeleter.components(home))
        for rel in ["Library", "Library/Caches", "Documents", "Downloads", ".Trash", "Library/Application Support"] {
            XCTAssertTrue(protected.contains(CleanupDeleter.components(home) + rel.split(separator: "/").map(String.init)), rel)
        }
        XCTAssertTrue(protected.contains(["/"]))
        XCTAssertTrue(protected.contains(CleanupDeleter.components("/System")))
        XCTAssertTrue(fakeTrashNames().isEmpty)
    }

    func testValidateRefusesRunningApp() throws {
        try write("Library/Caches/com.foo/x.bin", bytes: 2 * mb)
        let it = item(home + "/Library/Caches/com.foo", .appCaches)
        XCTAssertEqual(trasher(running: ["com.foo"]).validate(it), .appRunning)
        XCTAssertNil(trasher(running: ["com.other"]).validate(it))
    }

    func testValidateRefusesProtectedNames() throws {
        try write("Library/Caches/com.apple.Safari/x.bin", bytes: 2 * mb)
        try write("Library/Caches/CloudKit/x.bin", bytes: 2 * mb)
        try write("Library/Caches/com.foo/x.bin", bytes: 2 * mb)
        XCTAssertEqual(trasher().validate(item(home + "/Library/Caches/com.apple.Safari", .appCaches)), .nameNotAllowed)
        XCTAssertEqual(trasher().validate(item(home + "/Library/Caches/CloudKit", .appCaches)), .nameNotAllowed)
        XCTAssertEqual(trasher().validate(item(home + "/Library/Caches/com.foo", .trash)), .notUnderAllowedRoot)
    }

    // MARK: Taşıma ve günlük

    func testTrashMovesOnlyValidItemsAndLogs() throws {
        try write("Library/Caches/com.a/x.bin", bytes: 2 * mb)
        try write("Library/Caches/com.gone/x.bin", bytes: 2 * mb)
        try write("Library/Caches/com.run/x.bin", bytes: 2 * mb)
        try write("Library/Developer/Xcode/DerivedData/Proj/x.bin", bytes: 2 * mb)
        let running: Set<String> = ["com.run"]
        let items = scan(running: running).items
        XCTAssertEqual(items.count, 4)
        try FileManager.default.removeItem(at: fixture.appending(path: "Library/Caches/com.gone"))

        let results = trasher(running: running).delete(candidates(items), mode: .trash)
        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(fakeTrashNames(), ["Proj", "com.a"])
        XCTAssertEqual(results.filter(\.isRemoved).count, 2)
        let byName = Dictionary(uniqueKeysWithValues: results.map { ($0.candidate.name, $0.outcome) })
        XCTAssertEqual(byName["com.gone"], .skipped(.missing))
        XCTAssertEqual(byName["com.run"], .skipped(.appRunning))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home + "/Library/Caches/com.run/x.bin"))

        let lines = logLines()
        XCTAssertEqual(lines.count, 4, "öğe başına bir satır")
        let objs = try lines.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        XCTAssertEqual(objs.filter { $0["result"] as? String == "moved" }.count, 2)
        let skipped = objs.filter { $0["result"] as? String == "skipped" }
        XCTAssertEqual(Set(skipped.compactMap { $0["reason"] as? String }), ["missing", "appRunning"])
        let moved = try XCTUnwrap(objs.first { ($0["path"] as? String)?.hasSuffix("/com.a") == true })
        XCTAssertEqual(moved["trashedTo"] as? String, fakeTrash.appending(path: "com.a").path)
        XCTAssertEqual(moved["kind"] as? String, "junk.appCaches")
        XCTAssertEqual(moved["mode"] as? String, "trash")
        XCTAssertEqual(CleanupAuditLog.read(url: logURL, limit: 20).count, 4)
    }

    func testTrashPathCanonicalizationUnderPrivateVar() throws {
        try write("Library/Caches/com.foo/x.bin", bytes: 2 * mb)
        try XCTSkipUnless(home.hasPrefix("/var/"), "geçici klasör /var altında değil")
        XCTAssertNotEqual(CleanupDeleter.realPath(home), home)
        let t = trasher()
        XCTAssertNil(t.validate(item(home + "/Library/Caches/com.foo", .appCaches)))
        XCTAssertNil(t.validate(item("/private" + home + "/Library/Caches/com.foo", .appCaches)))
    }

    func testLogIsCappedAt500Lines() {
        let t = trasher()
        let ghosts = (0..<520).map { item("/nonexistent-cleanup-test/g\($0)", .appCaches) }
        let results = t.delete(ghosts, mode: .trash)
        XCTAssertTrue(results.allSatisfy { $0.outcome == .skipped(.notUnderAllowedRoot) || $0.outcome == .skipped(.missing) })
        XCTAssertEqual(logLines().count, CleanupAuditLog.limit)
        _ = t.delete([item("/nonexistent-cleanup-test/last", .appCaches)], mode: .trash)
        let lines = logLines()
        XCTAssertEqual(lines.count, CleanupAuditLog.limit)
        XCTAssertTrue(lines.last?.contains("/nonexistent-cleanup-test/last") == true)
        XCTAssertFalse(lines.contains { $0.contains("/nonexistent-cleanup-test/g0\"") })
    }

    // MARK: Bölümler ve proje klasörleri (görünüm modeli)

    @MainActor
    func testViewModelProjectFoldersAddRemoveAndScan() async throws {
        let suite = "cleanup-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = ProjectFoldersStore(defaults: UserDefaults(suiteName: suite)!, home: home)
        try write("Projects/web/node_modules/a.bin", bytes: 2 * mb)
        let vm = CleanupViewModel(home: home, folderStore: store)
        XCTAssertTrue(vm.projectFolders.isEmpty)
        XCTAssertNotNil(vm.addProjectFolder(home), "ev klasörünün kendisi reddedilir")
        XCTAssertNil(vm.addProjectFolder(home + "/Projects"))
        let folder = try XCTUnwrap(vm.projectFolders.first)
        XCTAssertEqual(vm.rootPaths(for: .projectArtifacts), [folder])
        XCTAssertNil(vm.state(of: .projectArtifacts))

        vm.scan([.projectArtifacts])
        for _ in 0..<100 where vm.isBusy { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(vm.state(of: .projectArtifacts), .scanned)
        XCTAssertEqual(vm.items(in: .projectArtifacts).map(\.name), ["node_modules"])
        XCTAssertTrue(vm.selection.isEmpty, "proje artıkları kendiliğinden seçilmez")

        vm.removeProjectFolder(folder)
        XCTAssertTrue(vm.projectFolders.isEmpty)
        XCTAssertTrue(vm.items(in: .projectArtifacts).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home + "/Projects/web/node_modules/a.bin"), "klasöre dokunulmaz")
    }

    func testGroupsSplitScanCategories() {
        XCTAssertEqual(Set(CleanupGroup.junk.scanCategories), [.appCaches, .browserCaches, .logs])
        XCTAssertEqual(Set(CleanupGroup.dev.scanCategories), [.derivedData, .archives, .deviceSupport, .simCaches, .pkgCaches])
    }
}
