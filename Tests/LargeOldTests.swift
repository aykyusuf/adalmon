import XCTest
@testable import Adalmon

final class LargeOldTests: XCTestCase {
    var root: String!

    override func setUpWithError() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "largeold-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = CleanupDeleter.realPath(url.path)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: root) }

    @discardableResult
    func write(_ rel: String, kb: Int, seed: UInt8 = 1) throws -> String {
        let path = root + "/" + rel
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        var data = Data(count: kb * 1024)
        for i in stride(from: 0, to: data.count, by: 4096) { data[i] = seed &+ UInt8(truncatingIfNeeded: i / 4096) }
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    func scanner(minKB: UInt64 = 200, stat: StatProvider = .live) -> LargeOldScanner {
        LargeOldScanner(minBytes: minKB * 1024, stat: stat)
    }

    func testListsOnlyFilesAtOrAboveThresholdLargestFirst() throws {
        try write("big.bin", kb: 600)
        try write("sub/mid.bin", kb: 300)
        try write("small.bin", kb: 20)
        let result = scanner().scan(roots: [root])
        XCTAssertEqual(result.items.map(\.name), ["big.bin", "mid.bin"])
        XCTAssertEqual(result.rootStates[root], .scanned)
        XCTAssertGreaterThanOrEqual(result.items[0].bytes, 600 * 1024)
    }

    func testOldFilterUsesModificationDate() throws {
        let old = try write("old.bin", kb: 300)
        try write("new.bin", kb: 300, seed: 9)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-400 * 86_400)], ofItemAtPath: old)
        let items = scanner().scan(roots: [root]).items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(LargeOldScanner.filter(items, onlyOld: true, olderThanDays: 365).map(\.name), ["old.bin"])
        XCTAssertEqual(LargeOldScanner.filter(items, onlyOld: true, olderThanDays: 730).count, 0)
        XCTAssertEqual(LargeOldScanner.filter(items, onlyOld: false, olderThanDays: 365).count, 2)
    }

    func testSymlinksAreNotFollowed() throws {
        let outside = FileManager.default.temporaryDirectory.appending(path: "outside-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(count: 400 * 1024).write(to: outside.appending(path: "secret.bin"))
        try write("real.bin", kb: 300)
        try FileManager.default.createSymbolicLink(atPath: root + "/link-dir", withDestinationPath: outside.path)
        try FileManager.default.createSymbolicLink(atPath: root + "/link-file.bin", withDestinationPath: outside.path + "/secret.bin")
        let names = scanner().scan(roots: [root]).items.map(\.name)
        XCTAssertEqual(names, ["real.bin"])
    }

    func testHardlinkCountedOnce() throws {
        let a = try write("a.bin", kb: 300)
        XCTAssertEqual(link(a, root + "/b.bin"), 0)
        XCTAssertEqual(scanner().scan(roots: [root]).items.count, 1)
    }

    func testDatalessFilesAreSkippedViaInjectedStat() throws {
        let cloud = try write("cloud.bin", kb: 300)
        try write("local.bin", kb: 300, seed: 5)
        let stat = StatProvider { path in
            guard var st = StatProvider.live.lstat(path) else { return nil }
            if path == cloud { st.flags |= FileStat.datalessFlag }
            return st
        }
        XCTAssertEqual(scanner(stat: stat).scan(roots: [root]).items.map(\.name), ["local.bin"])
    }

    func testPackageContentsAreSkipped() throws {
        try write("Thing.app/Contents/big.bin", kb: 300)
        try write("repo/.git/objects/pack.bin", kb: 300)
        try write("Photos.photoslibrary/originals/p.bin", kb: 300)
        try write("Music.musiclibrary/m.bin", kb: 300)
        try write("Cut.fcpbundle/f.bin", kb: 300)
        try write("repo/keep.bin", kb: 300, seed: 7)
        XCTAssertEqual(scanner().scan(roots: [root]).items.map(\.name), ["keep.bin"])
        XCTAssertTrue(FileWalker.isPackage(".git"))
        XCTAssertFalse(FileWalker.isPackage("notes.txt"))
    }

    func testCancellationStopsScan() throws {
        for i in 0..<20 { try write("f\(i).bin", kb: 300, seed: UInt8(i)) }
        var calls = 0
        let result = scanner().scan(roots: [root], isCancelled: { calls += 1; return calls > 5 })
        XCTAssertTrue(result.cancelled)
        XCTAssertLessThan(result.items.count, 20)
    }

    func testMissingRootIsReported() {
        let result = scanner().scan(roots: [root + "/nope"])
        XCTAssertEqual(result.rootStates[root + "/nope"], .missing)
        XCTAssertTrue(result.items.isEmpty)
    }

    func testCandidateUsesDescendantScopeAndDeleterAcceptsItInsideRoot() throws {
        let home = root + "/home"
        let docs = home + "/Documents"
        try FileManager.default.createDirectory(atPath: docs, withIntermediateDirectories: true)
        try write("home/Documents/big.bin", kb: 300)
        let item = try XCTUnwrap(scanner().scan(roots: [docs]).items.first)
        let candidate = item.candidate(roots: [docs])
        XCTAssertEqual(candidate.kind, "files.largeOld")
        XCTAssertEqual(candidate.scope, .descendant(roots: [docs], nameAllowlist: nil))
        let deleter = CleanupDeleter(home: home, runningBundleIDs: { [] }, logURL: URL(fileURLWithPath: root + "/log.jsonl"), ownPaths: [])
        XCTAssertNil(deleter.validate(candidate))
        // Seçilen kökün kendisi silinemez.
        var rootItem = candidate
        rootItem = DeletionCandidate(path: docs, dev: item.dev, ino: item.ino, bytes: 1, kind: rootItem.kind, scope: rootItem.scope, displayName: "Documents")
        XCTAssertNotNil(deleter.validate(rootItem))
    }

    @MainActor
    func testFileRootsStoreDefaultsAddRemoveAndRules() throws {
        let home = root + "/home"
        for dir in ["Downloads", "Documents", "Desktop", "Projects/a", "Library/Caches"] {
            try FileManager.default.createDirectory(atPath: home + "/" + dir, withIntermediateDirectories: true)
        }
        let suite = "largeold-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let canonicalHome = try XCTUnwrap(CleanupDeleter.realPath(home))
        let store = FileRootsStore(home: canonicalHome, defaults: defaults)
        XCTAssertEqual(store.roots, [canonicalHome + "/Downloads", canonicalHome + "/Documents", canonicalHome + "/Desktop"])
        XCTAssertTrue(store.isDefault)
        XCTAssertEqual(store.add(canonicalHome + "/Documents/x"), .notDirectory)
        XCTAssertEqual(store.add(canonicalHome + "/Documents"), .covered)
        XCTAssertEqual(store.add(canonicalHome + "/Library/Caches"), .notAllowed)
        XCTAssertEqual(store.add("/usr"), .notAllowed)
        XCTAssertEqual(store.add(canonicalHome + "/Projects/a"), .added)
        XCTAssertEqual(store.add(canonicalHome + "/Projects"), .added, "ata, alt kökün yerini alır")
        XCTAssertFalse(store.roots.contains(canonicalHome + "/Projects/a"))
        XCTAssertEqual(FileRootsStore(home: canonicalHome, defaults: defaults).roots, store.roots, "kalıcı")
        store.remove(canonicalHome + "/Projects")
        store.resetToDefaults()
        XCTAssertTrue(store.isDefault)
    }
}
