import XCTest
@testable import Adalmon

/// Sistem çöpü kuralları: günlükler ve tarayıcı önbellekleri (Chrome/Edge; Firefox yok). Yalnızca geçici sahte ev klasöründe çalışır.
final class JunkRulesTests: XCTestCase {
    private var fixture: URL!
    private var home: String { fixture.path }
    private var fakeTrash: URL { fixture.appending(path: "FakeTrash", directoryHint: .isDirectory) }
    private let mb = 1_048_576

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory.appending(path: "junk-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fixture)
    }

    @discardableResult
    private func write(_ rel: String, bytes: Int) throws -> URL {
        let url = fixture.appending(path: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 4096) { data[i] = UInt8(truncatingIfNeeded: i / 4096 + 1) }
        try data.write(to: url)
        return url
    }

    private func scan(_ categories: [CleanupCategory], running: Set<String> = []) -> CleanupScanner.Output {
        CleanupScanner.scan(categories: categories, home: home, runningBundleIDs: running, ownBundleID: nil)
    }

    private func deleter(running: Set<String> = []) -> CleanupDeleter {
        let trash = fakeTrash
        return CleanupDeleter(
            home: home, runningBundleIDs: { running }, logURL: fixture.appending(path: "log.jsonl"), ownPaths: [],
            moveToTrash: { url in
                let dest = trash.appending(path: url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            removePermanently: { _ in throw CocoaError(.featureUnsupported) }
        )
    }

    private func candidates(_ items: [CleanupItem]) -> [DeletionCandidate] {
        let roots = CleanupCatalog.roots(home: home, ownBundleID: nil)
        return items.map { DeletionCandidate(item: $0, roots: roots) }
    }

    private func writeBrowserFixture() throws {
        try write("Library/Caches/Google/Chrome/Default/c.bin", bytes: 2 * mb)
        try write("Library/Caches/com.google.Chrome/cache.bin", bytes: 2 * mb)
        try write("Library/Caches/Microsoft Edge/Default/e.bin", bytes: 2 * mb)
        try write("Library/Caches/com.microsoft.edgemac/cache.bin", bytes: 2 * mb)
        try write("Library/Caches/Firefox/Profiles/x/f.bin", bytes: 2 * mb)
        try write("Library/Caches/org.mozilla.firefox/f.bin", bytes: 2 * mb)
        try write("Library/Caches/com.foo/x.bin", bytes: 2 * mb)
    }

    // MARK: Kurallar

    func testBrowserFoldersAreSkippedByAppCachesIncludingFirefox() {
        let skips = CleanupCatalog.browserCacheSkipNames
        for name in ["Google", "com.google.Chrome", "Microsoft Edge", "com.microsoft.edgemac", "Firefox", "org.mozilla.firefox"] {
            XCTAssertTrue(skips.contains(name), name)
        }
        let app = CleanupCatalog.roots(home: home, ownBundleID: nil).first { $0.category == .appCaches }
        for name in skips { XCTAssertEqual(app?.allows(name), false, name) }
        XCTAssertEqual(app?.allows("com.foo"), true)
    }

    func testAppCachesNoLongerListsBrowserFolders() throws {
        try writeBrowserFixture()
        let names = scan([.appCaches]).items.map(\.name)
        XCTAssertEqual(names, ["com.foo"])
    }

    func testBrowserCachesListChromeAndEdgeOnly() throws {
        try writeBrowserFixture()
        let items = scan([.browserCaches]).items
        let paths = Set(items.map(\.path))
        XCTAssertEqual(paths, [
            home + "/Library/Caches/Google/Chrome/Default",
            home + "/Library/Caches/com.google.Chrome/cache.bin",
            home + "/Library/Caches/Microsoft Edge/Default",
            home + "/Library/Caches/com.microsoft.edgemac/cache.bin",
        ])
        XCTAssertTrue(items.allSatisfy { $0.category == .browserCaches })
        XCTAssertFalse(paths.contains { $0.localizedCaseInsensitiveContains("firefox") || $0.contains("mozilla") })
        // Hiçbir kategori Firefox klasörlerini üretmez.
        let all = scan(CleanupCategory.allCases.filter { $0 != .trash && $0 != .projectArtifacts }).items
        XCTAssertFalse(all.contains { $0.path.localizedCaseInsensitiveContains("firefox") || $0.path.contains("mozilla") })
        XCTAssertFalse(JunkRules.roots(home: home).contains { $0.path.localizedCaseInsensitiveContains("firefox") })
    }

    func testBrowserRunningBlocksAtScanTime() throws {
        try writeBrowserFixture()
        let out = scan([.browserCaches], running: ["com.google.Chrome"])
        for item in out.items {
            let isChrome = item.path.contains("Chrome")
            XCTAssertEqual(item.blockedReason, isChrome ? CleanupCatalog.runningBadge : nil, item.path)
            XCTAssertEqual(item.blockingBundleIDs, isChrome ? ["com.google.Chrome"] : ["com.microsoft.edgemac"], item.path)
        }
        XCTAssertEqual(JunkRules.runningBrowsers(["com.google.Chrome", "com.foo"]), ["Google Chrome"])
    }

    func testBrowserRunningBlocksAtDeleteTime() throws {
        try writeBrowserFixture()
        // Tarama sırasında tarayıcı kapalı, silme anında açık: silme reddedilir.
        let items = scan([.browserCaches]).items
        XCTAssertTrue(items.allSatisfy { $0.blockedReason == nil })
        let results = deleter(running: ["com.google.Chrome", "com.microsoft.edgemac"]).delete(candidates(items), mode: .trash)
        XCTAssertEqual(results.count, 4)
        XCTAssertTrue(results.allSatisfy { $0.outcome == .skipped(.appRunning) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: home + "/Library/Caches/Google/Chrome/Default/c.bin"))

        // Yalnızca Edge açık: Chrome öğeleri taşınır, Edge'inkiler kalır.
        let partial = deleter(running: ["com.microsoft.edgemac"]).delete(candidates(items), mode: .trash)
        XCTAssertEqual(Set(partial.filter(\.isRemoved).map(\.candidate.path)), [
            home + "/Library/Caches/Google/Chrome/Default", home + "/Library/Caches/com.google.Chrome/cache.bin",
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: home + "/Library/Caches/Microsoft Edge/Default/e.bin"))
    }

    func testBrowserKindAndCandidateScope() throws {
        try writeBrowserFixture()
        let item = try XCTUnwrap(scan([.browserCaches]).items.first { $0.path.hasSuffix("Chrome/Default") })
        let candidate = candidates([item])[0]
        XCTAssertEqual(candidate.kind, "junk.browserCaches")
        XCTAssertEqual(candidate.blockingBundleIDs, ["com.google.Chrome"])
        // Chrome klasörünün üstündeki Google klasörü ve komşusu doğrudan-çocuk kapsamına girmez.
        try write("Library/Caches/Google/Other/o.bin", bytes: 2 * mb)
        var other = item
        other = CleanupItem(path: home + "/Library/Caches/Google/Other", rootPath: home + "/Library/Caches/Google", category: .browserCaches,
                            bytes: item.bytes, isDirectory: true, modified: nil, dev: 0, ino: 0)
        XCTAssertNotNil(deleter().validate(candidates([other])[0]))
    }

    func testLogsListedButNotSelectedAndDiagnosticReportsSkipped() throws {
        try write("Library/Logs/Some.log", bytes: 2 * mb)
        try write("Library/Logs/AppLogs/a.log", bytes: 2 * mb)
        try write("Library/Logs/DiagnosticReports/crash.ips", bytes: 2 * mb)
        let out = scan([.logs])
        XCTAssertEqual(Set(out.items.map(\.name)), ["Some.log", "AppLogs"])
        XCTAssertFalse(CleanupCategory.logs.defaultSelected)
        XCTAssertEqual(CleanupCategory.logs.kind, "junk.logs")
        let results = deleter().delete(candidates(out.items.filter { $0.name == "Some.log" }), mode: .trash)
        XCTAssertEqual(results.filter(\.isRemoved).count, 1)
        let report = deleter().validate(DeletionCandidate(
            path: home + "/Library/Logs/DiagnosticReports", dev: 0, ino: 0, bytes: 0, kind: "junk.logs",
            scope: .directChild(roots: CleanupCatalog.roots(home: home, ownBundleID: nil).filter { $0.category == .logs }.map(\.deletionRoot)),
            displayName: "DiagnosticReports"))
        XCTAssertNotNil(report)
    }

    func testCatalogStaysUnderHomeWithUniquePaths() {
        let roots = CleanupCatalog.roots(home: home, ownBundleID: nil)
        for root in roots { XCTAssertTrue(root.path.hasPrefix(home + "/"), root.path) }
        XCTAssertEqual(Set(roots.map(\.path)).count, roots.count)
        XCTAssertTrue(CleanupCategory.browserCaches.defaultSelected)
        XCTAssertFalse(CleanupCategory.browserCaches.needsExplicitScan)
    }

    func testGroupsPartitionCategories() {
        let all = CleanupGroup.junk.categories + CleanupGroup.dev.categories
        XCTAssertEqual(Set(all).count, all.count)
        XCTAssertTrue(CleanupGroup.junk.categories.contains(.logs))
        XCTAssertTrue(CleanupGroup.junk.categories.contains(.browserCaches))
        XCTAssertTrue(CleanupGroup.dev.categories.contains(.projectArtifacts))
        XCTAssertFalse(CleanupGroup.dev.scanCategories.contains(.projectArtifacts))
        XCTAssertEqual(Set(all), Set(CleanupCategory.allCases.filter { $0 != .trash }))
    }
}
