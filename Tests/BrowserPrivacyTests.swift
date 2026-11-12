import XCTest
@testable import Adalmon

/// Tarayıcı gizlilik kuralları: sahte ev klasöründe profil fixture'ları. Gerçek tarayıcı verisine ya da gerçek Çöp Sepeti'ne dokunulmaz
/// (Çöp'e taşıma fixture içindeki FakeTrash'e yapılır).
final class BrowserPrivacyTests: XCTestCase {
    private var fixture: URL!
    private var home: String { fixture.path }
    private var fakeTrash: URL { fixture.appending(path: "FakeTrash", directoryHint: .isDirectory) }
    private var chromeRoot: String { home + "/Library/Application Support/Google/Chrome" }
    private var edgeRoot: String { home + "/Library/Application Support/Microsoft Edge" }

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory.appending(path: "privacy-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fixture)
    }

    // MARK: Yardımcılar

    @discardableResult
    private func write(_ path: String, _ text: String = "data") throws -> String {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return path
    }

    /// Chrome/Edge profili: tüm silinebilir dosyalar + dokunulmaması gereken dosyalar.
    private func makeProfile(_ root: String, _ name: String, networkCookies: Bool = false) throws {
        let dir = root + "/" + name
        for file in ["History", "History-journal", "Visited Links", "Top Sites"] { try write(dir + "/" + file) }
        if networkCookies {
            try write(dir + "/Network/Cookies")
            try write(dir + "/Network/Cookies-journal")
        } else {
            try write(dir + "/Cookies")
            try write(dir + "/Cookies-journal")
        }
        for keep in ["Bookmarks", "Login Data", "Login Data-journal", "Preferences", "Web Data"] { try write(dir + "/" + keep) }
    }

    private func makeSafari() throws {
        for f in ["History.db", "History.db-wal", "History.db-shm", "Bookmarks.plist"] { try write(home + "/Library/Safari/" + f) }
        try write(home + "/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")
        try write(home + "/Library/Cookies/Cookies.binarycookies")
    }

    private func scan(_ browser: PrivacyBrowser, running: Set<String> = [], probe: PathProbe = .live) -> BrowserPrivacyScan {
        BrowserPrivacyRules.scan(browser, home: home, running: running, probe: probe)
    }

    private func names(_ scan: BrowserPrivacyScan) -> [String] {
        scan.files.map { $0.path.replacingOccurrences(of: home + "/", with: "") }
    }

    private func deleter(running: Set<String> = []) -> CleanupDeleter {
        Self.makeDeleter(home: home, trash: fakeTrash, running: { running })
    }

    private static func makeDeleter(home: String, trash: URL, running: @escaping @Sendable () -> Set<String>) -> CleanupDeleter {
        CleanupDeleter(
            home: home, runningBundleIDs: running, logURL: trash.deletingLastPathComponent().appending(path: "log.jsonl"), ownPaths: [],
            moveToTrash: { url in
                let dest = trash.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            removePermanently: { try FileManager.default.removeItem(at: $0) }
        )
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    // MARK: Chrome / Edge

    func testChromeProfilesProduceOnlyHistoryAndCookieFiles() throws {
        try makeProfile(chromeRoot, "Default")
        try makeProfile(chromeRoot, "Profile 1")
        try makeProfile(chromeRoot, "Profile 12", networkCookies: true)
        try makeProfile(chromeRoot, "System Profile")
        try makeProfile(chromeRoot, "Guest Profile")
        try makeProfile(chromeRoot, "Profile X")
        let result = scan(.chrome)
        XCTAssertEqual(result.state, .scanned)
        XCTAssertEqual(result.profileCount, 3)
        let produced = Set(result.files.map { ($0.path as NSString).lastPathComponent })
        XCTAssertEqual(produced, ["History", "History-journal", "Visited Links", "Top Sites", "Cookies", "Cookies-journal"])
        // Hiçbir yasak ad üretilmez, yasak adlı hiçbir aday çıkmaz.
        for file in result.files {
            XCTAssertFalse(BrowserPrivacyRules.isDenied((file.path as NSString).lastPathComponent), file.path)
            XCTAssertFalse(file.path.contains("System Profile") || file.path.contains("Guest Profile") || file.path.contains("Profile X"), file.path)
        }
        let all = BrowserPrivacyRules.candidates(for: result, kinds: [.history, .cookies], running: [])
        XCTAssertEqual(all.count, result.files.count)
        for c in all {
            let name = c.name
            XCTAssertFalse(["Bookmarks", "Login Data", "Login Data-journal", "Preferences", "Web Data"].contains(name), c.path)
        }
        // Profil başına 8 dosya değil: Default 6, Profile 1 6, Profile 12 6 (Network/Cookies altında).
        XCTAssertEqual(result.files.count, 18)
    }

    func testNetworkCookiesPathIsSupported() throws {
        try makeProfile(chromeRoot, "Default", networkCookies: true)
        let result = scan(.chrome)
        XCTAssertTrue(names(result).contains("Library/Application Support/Google/Chrome/Default/Network/Cookies"))
        XCTAssertTrue(names(result).contains("Library/Application Support/Google/Chrome/Default/Network/Cookies-journal"))
        XCTAssertEqual(result.files(of: .cookies).count, 2)
        XCTAssertEqual(result.files(of: .history).count, 4)
        // Eski konum ve yeni konum birlikte olabilir.
        try write(chromeRoot + "/Default/Cookies")
        XCTAssertEqual(scan(.chrome).files(of: .cookies).count, 3)
    }

    func testEdgeUsesItsOwnFolder() throws {
        try makeProfile(edgeRoot, "Default")
        XCTAssertEqual(scan(.chrome).state, .notFound)
        let result = scan(.edge)
        XCTAssertEqual(result.state, .scanned)
        XCTAssertEqual(result.profileCount, 1)
        XCTAssertTrue(result.files.allSatisfy { $0.path.hasPrefix(edgeRoot + "/Default/") })
    }

    func testKindSelectionSeparatesHistoryAndCookies() throws {
        try makeProfile(chromeRoot, "Default")
        let result = scan(.chrome)
        let history = BrowserPrivacyRules.candidates(for: result, kinds: [.history], running: [])
        XCTAssertEqual(Set(history.map(\.name)), ["History", "History-journal", "Visited Links", "Top Sites"])
        let cookies = BrowserPrivacyRules.candidates(for: result, kinds: [.cookies], running: [])
        XCTAssertEqual(Set(cookies.map(\.name)), ["Cookies", "Cookies-journal"])
        XCTAssertTrue(BrowserPrivacyRules.candidates(for: result, kinds: [], running: []).isEmpty)
        // Aday bilgileri.
        XCTAssertTrue(history.allSatisfy { $0.kind == "privacy.chrome.history" && $0.blockingBundleIDs == ["com.google.Chrome"] })
        XCTAssertTrue(cookies.allSatisfy { $0.kind == "privacy.chrome.cookies" })
    }

    func testSymlinkedAndMissingFilesAreIgnored() throws {
        try makeProfile(chromeRoot, "Default")
        let target = try write(home + "/elsewhere/secret.db")
        let history = chromeRoot + "/Default/History"
        try FileManager.default.removeItem(atPath: history)
        try FileManager.default.createSymbolicLink(atPath: history, withDestinationPath: target)
        try FileManager.default.removeItem(atPath: chromeRoot + "/Default/Cookies")
        let result = scan(.chrome)
        XCTAssertFalse(result.files.contains { $0.path == history })
        XCTAssertFalse(result.files.contains { $0.path.hasSuffix("/Cookies") })
        XCTAssertTrue(result.files.contains { $0.path.hasSuffix("/History-journal") })
    }

    // MARK: Açık tarayıcı

    func testRunningBrowserIsRefusedAtScan() throws {
        try makeProfile(chromeRoot, "Default")
        try makeProfile(edgeRoot, "Default")
        let running: Set<String> = ["com.google.Chrome"]
        let chrome = scan(.chrome, running: running)
        XCTAssertEqual(chrome.state, .running)
        XCTAssertTrue(chrome.files.isEmpty)
        XCTAssertTrue(BrowserPrivacyRules.candidates(for: chrome, kinds: [.history, .cookies], running: running).isEmpty)
        // Diğer tarayıcı etkilenmez.
        XCTAssertEqual(scan(.edge, running: running).state, .scanned)
        XCTAssertEqual(BrowserPrivacyRules.closeFirstText(.chrome), "Önce Chrome'u kapatın")
        for (browser, id) in [(PrivacyBrowser.chrome, "com.google.Chrome"), (.edge, "com.microsoft.edgemac"), (.safari, "com.apple.Safari")] {
            XCTAssertEqual(browser.bundleID, id)
        }
    }

    func testCandidatesRefuseWhenBrowserOpensAfterScan() throws {
        try makeProfile(chromeRoot, "Default")
        let result = scan(.chrome)
        XCTAssertTrue(BrowserPrivacyRules.candidates(for: result, kinds: [.history], running: ["com.google.Chrome"]).isEmpty)
    }

    func testDeleterRefusesWhenBrowserRunsAtDeleteTime() throws {
        try makeProfile(chromeRoot, "Default")
        let candidates = BrowserPrivacyRules.candidates(for: scan(.chrome), kinds: [.history, .cookies], running: [])
        XCTAssertFalse(candidates.isEmpty)
        let results = deleter(running: ["com.google.Chrome"]).delete(candidates, mode: .trash)
        XCTAssertEqual(results.count, candidates.count)
        XCTAssertTrue(results.allSatisfy { $0.outcome == .skipped(.appRunning) })
        XCTAssertTrue(exists(chromeRoot + "/Default/History"))
    }

    // MARK: Silme (CleanupDeleter üzerinden)

    func testTrashingMovesOnlyHistoryAndCookiesAndKeepsBookmarksAndLogins() throws {
        try makeProfile(chromeRoot, "Default", networkCookies: true)
        try makeProfile(chromeRoot, "Profile 1")
        let candidates = BrowserPrivacyRules.candidates(for: scan(.chrome), kinds: [.history, .cookies], running: [])
        let results = deleter().delete(candidates, mode: .trash)
        XCTAssertTrue(results.allSatisfy(\.isRemoved), "\(results.compactMap(\.reasonText))")
        for profile in ["Default", "Profile 1"] {
            for gone in ["History", "History-journal", "Visited Links", "Top Sites"] {
                XCTAssertFalse(exists("\(chromeRoot)/\(profile)/\(gone)"), "\(profile)/\(gone)")
            }
            for keep in ["Bookmarks", "Login Data", "Login Data-journal", "Preferences", "Web Data"] {
                XCTAssertTrue(exists("\(chromeRoot)/\(profile)/\(keep)"), "\(profile)/\(keep)")
            }
        }
        XCTAssertFalse(exists(chromeRoot + "/Default/Network/Cookies"))
        XCTAssertFalse(exists(chromeRoot + "/Profile 1/Cookies"))
    }

    func testPermanentDeleteRemovesOnlyChosenKind() throws {
        try makeProfile(chromeRoot, "Default")
        let candidates = BrowserPrivacyRules.candidates(for: scan(.chrome), kinds: [.cookies], running: [])
        let results = deleter().delete(candidates, mode: .permanent)
        XCTAssertTrue(results.allSatisfy { $0.outcome == .deleted })
        XCTAssertFalse(exists(chromeRoot + "/Default/Cookies"))
        XCTAssertTrue(exists(chromeRoot + "/Default/History"))
        XCTAssertTrue(exists(chromeRoot + "/Default/Bookmarks"))
        XCTAssertTrue(exists(chromeRoot + "/Default/Login Data"))
    }

    func testDeleterRefusesProtectedSiblingsWithExactScope() throws {
        try makeProfile(chromeRoot, "Default")
        let result = scan(.chrome)
        let history = try XCTUnwrap(result.files.first { $0.path.hasSuffix("/History") })
        // Aynı aday başka bir dosyaya yönlendirilirse (kimlik/kapsam uyumsuz) reddedilir.
        let forged = DeletionCandidate(path: chromeRoot + "/Default/Bookmarks", dev: history.dev, ino: history.ino, bytes: 1, kind: "privacy.chrome.history",
                                       scope: .exactFile(allowed: [history.path]), displayName: "x")
        XCTAssertNotNil(deleter().validate(forged))
        XCTAssertTrue(exists(chromeRoot + "/Default/Bookmarks"))
    }

    func testDenyList() {
        for name in ["Bookmarks", "Login Data", "Login Data-journal", "Login Data For Account", "Preferences", "Secure Preferences", "Web Data"] {
            XCTAssertTrue(BrowserPrivacyRules.isDenied(name), name)
        }
        for name in ["History", "Cookies", "Visited Links", "Top Sites", "History.db", "Cookies.binarycookies"] {
            XCTAssertFalse(BrowserPrivacyRules.isDenied(name), name)
        }
    }

    // MARK: Safari

    func testSafariFiles() throws {
        try makeSafari()
        let result = scan(.safari)
        XCTAssertEqual(result.state, .scanned)
        XCTAssertEqual(Set(names(result)), [
            "Library/Safari/History.db", "Library/Safari/History.db-wal", "Library/Safari/History.db-shm",
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
            "Library/Cookies/Cookies.binarycookies",
        ])
        XCTAssertEqual(result.files(of: .history).count, 3)
        XCTAssertEqual(result.files(of: .cookies).count, 2)
        // Yer imleri hiçbir koşulda aday değil ve silmeden sonra yerinde.
        let candidates = BrowserPrivacyRules.candidates(for: result, kinds: [.history, .cookies], running: [])
        let results = deleter().delete(candidates, mode: .trash)
        XCTAssertTrue(results.allSatisfy(\.isRemoved), "\(results.compactMap(\.reasonText))")
        XCTAssertFalse(exists(home + "/Library/Safari/History.db"))
        XCTAssertTrue(exists(home + "/Library/Safari/Bookmarks.plist"))
    }

    func testSafariWithoutFullDiskAccessReportsNoAccess() throws {
        try makeSafari()
        let denied = PathProbe { path in path.hasSuffix("/Library/Safari") ? .denied : .ok }
        let result = scan(.safari, probe: denied)
        XCTAssertEqual(result.state, .noAccess)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.blockedPath, home + "/Library/Safari")
        XCTAssertEqual(CleanupAccess.reason(for: result.blockedPath ?? "", home: home), .fullDiskAccess)
        // Yalnızca çerez klasörü reddedilirse de erişim akışı çalışır.
        let deniedCookies = PathProbe { path in path.hasSuffix("/Library/Cookies") ? .denied : .ok }
        XCTAssertEqual(scan(.safari, probe: deniedCookies).state, .noAccess)
    }

    func testSafariMissingFolders() {
        XCTAssertEqual(scan(.safari).state, .notFound)
        XCTAssertEqual(scan(.chrome).state, .notFound)
        XCTAssertEqual(scan(.edge).state, .notFound)
    }

    func testSafariRunningIsRefused() throws {
        try makeSafari()
        let result = scan(.safari, running: ["com.apple.Safari"])
        XCTAssertEqual(result.state, .running)
        XCTAssertTrue(result.files.isEmpty)
    }

    // MARK: Metinler

    func testLossLinesNameWhatIsLost() {
        let both = BrowserPrivacyRules.lossLines(browser: .chrome, kinds: [.history, .cookies]).joined(separator: " ")
        XCTAssertTrue(both.contains("geçmişi silinir"))
        XCTAssertTrue(both.contains("Tüm sitelerden çıkış yapılır"))
        let historyOnly = BrowserPrivacyRules.lossLines(browser: .edge, kinds: [.history]).joined()
        XCTAssertFalse(historyOnly.contains("çıkış"))
        XCTAssertEqual(BrowserPrivacyRules.closeFirstText(.edge), "Önce Edge'i kapatın")
        XCTAssertEqual(BrowserPrivacyRules.closeFirstText(.safari), "Önce Safari'yi kapatın")
    }

    // MARK: Model

    @MainActor
    func testViewModelRefusesDeletionRequestWhenBrowserIsOpen() throws {
        try makeProfile(chromeRoot, "Default")
        let box = RunningBox()
        let vm = BrowserPrivacyViewModel(home: home, runningBundleIDs: { box.value }, makeDeleter: { [home, trash = fakeTrash] in Self.makeDeleter(home: home, trash: trash, running: { box.value }) })
        vm.apply(BrowserPrivacyRules.scanAll(home: home, running: [], probe: .live))
        vm.toggle(.history, in: .chrome)
        XCTAssertEqual(vm.selectedTotals(.chrome).count, 4)
        XCTAssertNotNil(vm.requestDeletion(of: .chrome))
        // Tarayıcı taramadan sonra açıldı: istek reddedilir, kart "açık" olur.
        box.value = ["com.google.Chrome"]
        XCTAssertNil(vm.requestDeletion(of: .chrome))
        XCTAssertEqual(vm.scan(for: .chrome)?.state, .running)
        XCTAssertTrue(exists(chromeRoot + "/Default/History"))
    }

    @MainActor
    func testViewModelSelectionKeepsOnlyAvailableKinds() throws {
        try write(chromeRoot + "/Default/History")
        let vm = BrowserPrivacyViewModel(home: home, runningBundleIDs: { [] })
        vm.apply(BrowserPrivacyRules.scanAll(home: home, running: [], probe: .live))
        vm.toggle(.cookies, in: .chrome) // çerez dosyası yok
        vm.apply(BrowserPrivacyRules.scanAll(home: home, running: [], probe: .live))
        XCTAssertTrue(vm.selected(.chrome).isEmpty)
        XCTAssertNil(vm.requestDeletion(of: .chrome))
        XCTAssertEqual(vm.deleteMode, .trash)
    }

    private final class RunningBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Set<String> = []
        var value: Set<String> {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }
}
