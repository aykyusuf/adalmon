import XCTest
@testable import Adalmon

/// Çok tarayıcılı silme zinciri: sahte ev klasörü + sahte Çöp. Gerçek tarayıcı verisine dokunulmaz.
@MainActor
final class PrivacyDeletionRunTests: XCTestCase {
    private var fixture: URL!
    private var home: String { fixture.path }
    private var fakeTrash: URL { fixture.appending(path: "FakeTrash", directoryHint: .isDirectory) }

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory.appending(path: "privacy-run-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: fixture) }

    private func write(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("data".utf8).write(to: url)
    }

    private func makeProfile(_ root: String) throws {
        for f in ["History", "Cookies", "Bookmarks", "Login Data"] { try write(root + "/Default/" + f) }
    }

    func testRunDeletesEveryBrowserInTheBatchAndKeepsBookmarksAndLogins() async throws {
        let chrome = home + "/Library/Application Support/Google/Chrome"
        let edge = home + "/Library/Application Support/Microsoft Edge"
        try makeProfile(chrome)
        try makeProfile(edge)
        let trash = fakeTrash, home = home
        let vm = BrowserPrivacyViewModel(home: home, runningBundleIDs: { [] }, makeDeleter: {
            CleanupDeleter(home: home, runningBundleIDs: { [] }, logURL: trash.deletingLastPathComponent().appending(path: "log.jsonl"), ownPaths: [],
                           moveToTrash: { url in
                               let dest = trash.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
                               try FileManager.default.moveItem(at: url, to: dest)
                               return dest
                           },
                           removePermanently: { try FileManager.default.removeItem(at: $0) })
        })
        vm.apply(BrowserPrivacyRules.scanAll(home: home, running: []))
        for browser in [PrivacyBrowser.chrome, .edge] {
            vm.toggle(.history, in: browser)
            vm.toggle(.cookies, in: browser)
        }
        let pendings = try [PrivacyBrowser.chrome, .edge].map { try XCTUnwrap(vm.requestDeletion(of: $0)) }
        let results = await PrivacyDeletionRun.run(pendings, mode: .trash, on: vm)

        XCTAssertEqual(results.filter(\.isRemoved).count, 4)
        XCTAssertEqual(vm.phase, .idle)
        let fm = FileManager.default
        for root in [chrome, edge] {
            XCTAssertFalse(fm.fileExists(atPath: root + "/Default/History"))
            XCTAssertFalse(fm.fileExists(atPath: root + "/Default/Cookies"))
            XCTAssertTrue(fm.fileExists(atPath: root + "/Default/Bookmarks"))
            XCTAssertTrue(fm.fileExists(atPath: root + "/Default/Login Data"))
        }
        let summary = PrivacyFreed(results: results, mode: .trash)
        XCTAssertEqual(summary.count, 4)
        XCTAssertTrue(summary.skipped.isEmpty)
    }

    func testRunStopsWhenBrowserOpensBeforeItsTurn() async throws {
        let chrome = home + "/Library/Application Support/Google/Chrome"
        try makeProfile(chrome)
        let box = RunningBox()
        let trash = fakeTrash, home = home
        let vm = BrowserPrivacyViewModel(home: home, runningBundleIDs: { box.value }, makeDeleter: {
            CleanupDeleter(home: home, runningBundleIDs: { box.value }, logURL: trash.deletingLastPathComponent().appending(path: "log.jsonl"), ownPaths: [],
                           moveToTrash: { url in
                               let dest = trash.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
                               try FileManager.default.moveItem(at: url, to: dest)
                               return dest
                           },
                           removePermanently: { try FileManager.default.removeItem(at: $0) })
        })
        vm.apply(BrowserPrivacyRules.scanAll(home: home, running: []))
        vm.toggle(.history, in: .chrome)
        let pending = try XCTUnwrap(vm.requestDeletion(of: .chrome))
        box.value = ["com.google.Chrome"]
        let results = await PrivacyDeletionRun.run([pending], mode: .trash, on: vm)
        XCTAssertTrue(results.filter(\.isRemoved).isEmpty, "Silme anında açık tarayıcı reddedilmeli")
        XCTAssertTrue(FileManager.default.fileExists(atPath: chrome + "/Default/History"))
    }
}

private final class RunningBox: @unchecked Sendable {
    private let lock = NSLock()
    private var set: Set<String> = []
    var value: Set<String> {
        get { lock.withLock { set } }
        set { lock.withLock { set = newValue } }
    }
}
