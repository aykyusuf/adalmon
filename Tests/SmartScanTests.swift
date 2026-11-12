import XCTest
@testable import Adalmon

/// Tüm testler geçici bir sahte ev klasöründe çalışır; gerçek ev klasörlerine dokunmaz.
final class SmartScanTests: XCTestCase {
    private var fixture: URL!
    private var home: String { fixture.path }
    private let mb = 1_048_576
    private let now = Date()

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory.appending(path: "smartscan-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
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

    /// Klasör ağacının tüm değişiklik zamanlarını `days` gün öncesine çeker (en derinden başlayarak; yazma üst klasörü değiştirmesin).
    private func backdate(_ rel: String, days: Double) throws {
        let root = fixture.appending(path: rel)
        let date = now.addingTimeInterval(-days * 86_400)
        var all: [URL] = [root]
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in e { all.append(url) }
        }
        for url in all.reversed() { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
    }

    /// Güvenli ve riskli türlerin hepsini içeren sahte ev.
    private func populate() throws {
        try write("Library/Caches/com.example.big/blob.bin", bytes: 3 * mb)
        try write("Library/Caches/com.example.running/blob.bin", bytes: 2 * mb)
        try write("Library/Caches/Google/Chrome/Default/blob.bin", bytes: 4 * mb)
        try write("Library/Developer/Xcode/DerivedData/App-abc/blob.bin", bytes: 5 * mb)
        try write("Library/Developer/CoreSimulator/Caches/dyld/blob.bin", bytes: 2 * mb)
        try write("Library/Logs/App/log.bin", bytes: 2 * mb)
        try write(".Trash/old.bin", bytes: 6 * mb)
        // Yalnızca incele türleri.
        try write("Downloads/huge.dmg", bytes: 101 * mb)
        try write("Library/Application Support/com.gone.orphan/blob.bin", bytes: 2 * mb)
        // Başka riskli türler: taranmamalı.
        try write("Library/Application Support/MobileSync/Backup/dev1/blob.bin", bytes: 3 * mb)
        try write("Library/Developer/Xcode/Archives/2026/a.xcarchive/blob.bin", bytes: 2 * mb)
        try write("Library/Developer/Xcode/iOS DeviceSupport/17.0/blob.bin", bytes: 2 * mb)
        // Proje artıkları: ortak köklerde (Developer, Documents, Desktop).
        try write("Developer/old-web/package.json", bytes: 10)
        try write("Developer/old-web/node_modules/pkg/index.js", bytes: 2 * mb)
        try write("Documents/fresh-web/package.json", bytes: 10)
        try write("Documents/fresh-web/node_modules/pkg/index.js", bytes: 2 * mb)
        try write("Desktop/old-app/Package.swift", bytes: 10)
        try write("Desktop/old-app/.build/debug/app.o", bytes: 2 * mb)
        try write("Developer/old-rust/Cargo.toml", bytes: 10)
        try write("Developer/old-rust/target/debug/x.o", bytes: 2 * mb)
        try backdate("Developer/old-web", days: 120)
        try backdate("Desktop/old-app", days: 45)
        try backdate("Developer/old-rust", days: 200)
        try backdate("Documents/fresh-web", days: 3)
    }

    private func scanAll(running: Set<String> = [], probe: PathProbe = .live, projectFolders: [String] = [],
                         isCancelled: @escaping () -> Bool = { false },
                         stepFinished: @escaping (SmartScanStepResult) -> Void = { _ in }) -> SmartScanResult {
        SmartScanAggregator.run(home: home, runningBundleIDs: running, ownBundleID: nil, projectFolders: projectFolders,
                                appRoots: [], orphanResolver: { _ in false }, now: now, probe: probe,
                                isCancelled: isCancelled, stepFinished: stepFinished)
    }

    private func names(_ result: SmartScanResult, _ step: SmartScanStep) -> [String] {
        (result.results[step]?.items ?? []).map { SmartScanPresentation.projectName($0) + "/" + $0.name }.sorted()
    }

    // MARK: Toplama

    func testAggregatesAllStepsOverFixtureHome() throws {
        try populate()
        let result = scanAll()
        XCTAssertFalse(result.wasCancelled)
        XCTAssertEqual(result.completed, SmartScanStep.allCases)
        XCTAssertTrue(result.notRun.isEmpty)

        XCTAssertEqual(Set(result.results[.appCaches]?.items.map(\.name) ?? []), ["com.example.big", "com.example.running"])
        XCTAssertEqual(result.results[.browserCaches]?.items.count, 1)
        XCTAssertEqual(result.results[.logs]?.items.map(\.name), ["App"])
        XCTAssertEqual(result.results[.devCaches]?.items.count, 2)
        XCTAssertGreaterThanOrEqual(result.results[.trash]?.trashBytes ?? 0, UInt64(6 * mb))
        XCTAssertTrue(result.results[.trash]?.items.isEmpty ?? false)

        let expected = SmartScanStep.allCases.filter(\.isCleanable).reduce(UInt64(0)) { $0 + (result.results[$1]?.cleanableBytes ?? 0) }
        XCTAssertEqual(result.cleanableBytes(), expected)
        XCTAssertGreaterThanOrEqual(result.cleanableBytes(), UInt64(24 * mb))
    }

    func testAutoRootsFindNodeModulesAndDerivedDataWithoutAnyProjectFolder() throws {
        try populate()
        try write("Projects/ios-app/App.xcodeproj/project.pbxproj", bytes: 10)
        try write("Projects/ios-app/DerivedData/Build/blob.bin", bytes: 2 * mb)
        let result = scanAll()
        let found = names(result, .projectArtifacts)
        XCTAssertEqual(found, ["fresh-web/node_modules", "ios-app/DerivedData", "old-app/.build", "old-rust/target", "old-web/node_modules"])
        // Kütüphane DerivedData'sı geliştirici önbelleği adımında.
        XCTAssertTrue(result.results[.devCaches]?.items.contains { $0.category == .derivedData } ?? false)
        let states = try XCTUnwrap(result.results[.projectArtifacts]?.rootStates)
        XCTAssertEqual(Set(states.keys.map { ($0 as NSString).lastPathComponent }), ["Developer", "Documents", "Desktop", "Projects"])
        XCTAssertTrue(states.values.allSatisfy { $0 == .scanned })
    }

    func testSearchRootsOnlyExistingRealDirectoriesPlusUserFoldersWithoutDuplicates() throws {
        try FileManager.default.createDirectory(at: fixture.appending(path: "Code"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixture.appending(path: "Elsewhere/work"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixture.appending(path: "RealGit"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.appending(path: "GitHub"), withDestinationURL: fixture.appending(path: "RealGit"))
        let roots = SmartScanAggregator.projectSearchRoots(home: home, userFolders: [home + "/Elsewhere/work", home + "/Code"])
        XCTAssertEqual(roots, [home + "/Elsewhere/work", home + "/Code"])
    }

    // MARK: Seçim

    func testProjectArtifactsOlderThan30DaysAreSelectedNewerAreNot() throws {
        try populate()
        let result = scanAll()
        let selection = SmartScanSelection.defaultSelection(result, now: now)
        let artifacts = try XCTUnwrap(result.results[.projectArtifacts]).items
        XCTAssertEqual(artifacts.count, 4)
        for item in artifacts {
            let project = SmartScanPresentation.projectName(item)
            XCTAssertEqual(selection.contains(item.id), project != "fresh-web", "\(project) seçimi yanlış")
        }
        let fresh = try XCTUnwrap(artifacts.first { SmartScanPresentation.projectName($0) == "fresh-web" })
        XCTAssertTrue(SmartScanPresentation.detail(fresh, home: home, now: now).contains("son 30 günde kullanılmış, seçilmedi"))
        let old = try XCTUnwrap(artifacts.first { SmartScanPresentation.projectName($0) == "old-web" })
        XCTAssertFalse(SmartScanPresentation.detail(old, home: home, now: now).contains("seçilmedi"))
    }

    func testRecentActivityInProjectFolderKeepsOldArtifactUnselected() throws {
        try populate()
        // node_modules eski, ama proje klasöründe yeni bir dosya var (ör. git işlemi / düzenleme).
        try write("Developer/old-web/src.ts", bytes: 10)
        let result = scanAll()
        let item = try XCTUnwrap(result.results[.projectArtifacts]?.items.first { SmartScanPresentation.projectName($0) == "old-web" })
        XCTAssertTrue(SmartScanSelection.isRecent(item, now: now))
        XCTAssertFalse(SmartScanSelection.defaultSelection(result, now: now).contains(item.id))
    }

    func testLogsAndNonDefaultKindsAreListedButNotSelected() throws {
        try populate()
        let result = scanAll()
        let selection = SmartScanSelection.defaultSelection(result, now: now)
        let logs = try XCTUnwrap(result.results[.logs]?.items)
        XCTAssertFalse(logs.isEmpty)
        XCTAssertTrue(logs.allSatisfy { !selection.contains($0.id) })
        for item in result.allCleanableItems where item.category.defaultSelected {
            XCTAssertTrue(selection.contains(item.id), "\(item.name) varsayılan seçili olmalı")
        }
    }

    func testRunningAppsBrowsersAndXcodeAreBlockedAndNeverSelected() throws {
        try populate()
        try write("Projects/ios-app/Package.swift", bytes: 10)
        try write("Projects/ios-app/DerivedData/Build/blob.bin", bytes: 2 * mb)
        try backdate("Projects/ios-app", days: 100)
        let result = scanAll(running: ["com.google.Chrome", "com.example.running", CleanupCatalog.xcodeBundleID])
        let browser = try XCTUnwrap(result.results[.browserCaches])
        XCTAssertEqual(browser.runningBrowsers, ["Google Chrome"])
        XCTAssertEqual(browser.cleanableItems.count, 0)
        XCTAssertGreaterThan(browser.blockedBytes, 0)
        let app = try XCTUnwrap(result.results[.appCaches])
        XCTAssertEqual(app.cleanableItems.map(\.name), ["com.example.big"])
        XCTAssertEqual(app.blockedItems.map(\.name), ["com.example.running"])
        // Xcode açıkken proje içi DerivedData ve kütüphane DerivedData'sı engelli.
        let derived = try XCTUnwrap(result.results[.projectArtifacts]?.items.first { $0.name == "DerivedData" })
        XCTAssertNotNil(derived.blockedReason)
        XCTAssertTrue(result.results[.devCaches]?.items.filter { $0.category == .derivedData }.allSatisfy { $0.blockedReason != nil } ?? false)
        let selection = SmartScanSelection.defaultSelection(result, now: now)
        XCTAssertFalse(selection.contains(derived.id))
        XCTAssertTrue(result.allCleanableItems.allSatisfy { $0.blockedReason == nil })
        let candidates = result.deletionCandidates(roots: CleanupCatalog.roots(home: home, ownBundleID: nil))
        XCTAssertFalse(candidates.contains { $0.name == "com.example.running" || $0.name == "DerivedData" })
    }

    func testLargeFilesAndOrphansAreCountedButNeverSelectable() throws {
        try populate()
        let result = scanAll()
        let large = try XCTUnwrap(result.results[.largeFiles])
        XCTAssertEqual(large.reviewCount, 1)
        XCTAssertGreaterThanOrEqual(large.reviewBytes, UInt64(101 * mb))
        let orphans = try XCTUnwrap(result.results[.orphans])
        // Kurulu uygulaması olmayan üç kimlik: com.gone.orphan ve önbellekteki iki com.example.* klasörü.
        XCTAssertEqual(orphans.reviewCount, 3)
        XCTAssertGreaterThanOrEqual(orphans.reviewBytes, UInt64(7 * mb))
        // Hiçbiri öğe olarak listelenmez, seçime ve silme adaylarına girmez.
        XCTAssertTrue(large.items.isEmpty && orphans.items.isEmpty)
        XCTAssertFalse(SmartScanStep.largeFiles.isCleanable || SmartScanStep.orphans.isCleanable || SmartScanStep.trash.isCleanable)
        XCTAssertEqual(result.cleanableItems(steps: [.largeFiles, .orphans, .trash]).count, 0)
        let selection = SmartScanSelection.defaultSelection(result, now: now)
        let candidates = result.deletionCandidates(roots: CleanupCatalog.roots(home: home, ownBundleID: nil))
        XCTAssertTrue(candidates.allSatisfy { !$0.path.contains("/Downloads/") && !$0.path.contains("com.gone.orphan") })
        XCTAssertTrue(candidates.allSatisfy { !$0.path.contains("MobileSync") && !$0.path.contains("Archives") && !$0.path.contains("DeviceSupport") })
        XCTAssertTrue(selection.isSubset(of: Set(result.allCleanableItems.map(\.id))))
        // Çalışan ya da kurulu uygulama kimliği yetim sayılmaz.
        let installed = SmartScanAggregator.run(home: home, runningBundleIDs: ["com.gone.orphan", "com.example.big", "com.example.running"],
                                                ownBundleID: nil, steps: [.orphans],
                                                appRoots: [], orphanResolver: { _ in false }, now: now)
        XCTAssertEqual(installed.results[.orphans]?.reviewCount, 0)
        // Yalnızca kopyalar ve gizlilik "İncele" kartıdır.
        XCTAssertEqual(Set(SmartScanReviewKind.allCases.map(\.rawValue)), ["duplicates", "privacy"])
        XCTAssertTrue(SmartScanReviewKind.allCases.allSatisfy { $0.subsection != .smartScan })
        XCTAssertTrue(SmartScanStep.allCases.allSatisfy { $0.subsection != .smartScan })
    }

    func testRiskyCategoriesAreNeverScanned() throws {
        try populate()
        let result = scanAll()
        let risky: Set<CleanupCategory> = [.archives, .deviceSupport, .iosBackups, .downloads]
        XCTAssertTrue(result.results.values.flatMap(\.items).allSatisfy { !risky.contains($0.category) })
        XCTAssertTrue(SmartScanAggregator.scannedCategories.isDisjoint(with: [.archives, .deviceSupport, .iosBackups]))
        let candidates = result.deletionCandidates(roots: CleanupCatalog.roots(home: home, ownBundleID: nil))
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { !$0.path.contains("/Downloads/") })
    }

    // MARK: TCC, iptal, sıra

    func testDeniedRootIsSkippedAndReportedWhileOthersAreScanned() throws {
        try populate()
        let documents = home + "/Documents"
        let probe = PathProbe { path in
            if path == documents { return .denied }
            return PathProbe.live.check(path)
        }
        let result = scanAll(probe: probe)
        let step = try XCTUnwrap(result.results[.projectArtifacts])
        XCTAssertEqual(step.rootStates[documents], .noAccess)
        XCTAssertEqual(step.deniedRoots, [documents])
        XCTAssertEqual(step.rootStates[home + "/Developer"], .scanned)
        XCTAssertEqual(names(result, .projectArtifacts), ["old-app/.build", "old-rust/target", "old-web/node_modules"])
        XCTAssertEqual(step.state, .scanned)
        XCTAssertEqual(SmartScanPresentation.deniedText(step.deniedRoots, home: home), "~/Documents")
    }

    func testCancelBeforeStartRunsNothing() throws {
        try populate()
        let result = scanAll(isCancelled: { true })
        XCTAssertTrue(result.wasCancelled)
        XCTAssertTrue(result.results.isEmpty)
        XCTAssertEqual(result.notRun, SmartScanStep.allCases)
    }

    func testCancelAfterFirstStepStopsSubsequentSteps() throws {
        try populate()
        var cancelled = false
        let result = scanAll(isCancelled: { cancelled }, stepFinished: { _ in cancelled = true })
        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.completed, [.appCaches])
        XCTAssertNil(result.results[.projectArtifacts])
        XCTAssertEqual(result.notRun, Array(SmartScanStep.allCases.dropFirst()))
    }

    func testCancelInsideProjectStepDropsPartialResult() throws {
        try populate()
        var calls = 0
        // Proje adımına girene kadar iptal yok; sonra ilk denetimde iptal.
        let result = SmartScanAggregator.run(home: home, runningBundleIDs: [], ownBundleID: nil, appRoots: [], orphanResolver: { _ in false },
                                             now: now, isCancelled: { calls += 1; return false },
                                             stepStarted: { _ in })
        XCTAssertFalse(result.wasCancelled)
        var cancelNow = false
        let cut = SmartScanAggregator.run(home: home, runningBundleIDs: [], ownBundleID: nil, appRoots: [], orphanResolver: { _ in false },
                                          now: now, isCancelled: { cancelNow },
                                          stepStarted: { if $0 == .projectArtifacts { cancelNow = true } })
        XCTAssertTrue(cut.wasCancelled)
        XCTAssertNil(cut.results[.projectArtifacts], "adım içinde iptal edilen adımın yarım sonucu atılır")
        XCTAssertEqual(cut.completed, [.appCaches, .logs, .browserCaches, .devCaches])
    }

    func testStepsRunInOrderAndReportProgress() throws {
        try populate()
        var started: [SmartScanStep] = []
        var details: [String] = []
        _ = SmartScanAggregator.run(home: home, runningBundleIDs: [], ownBundleID: nil, appRoots: [], orphanResolver: { _ in false },
                                    stepStarted: { started.append($0) }, detail: { details.append($0) })
        XCTAssertEqual(started, [.appCaches, .logs, .browserCaches, .devCaches, .projectArtifacts, .trash, .largeFiles, .orphans])
        XCTAssertTrue(details.contains("Developer"))
    }

    func testEmptyHomeReportsMissingAndZero() {
        let result = scanAll()
        XCTAssertEqual(result.completed, SmartScanStep.allCases)
        XCTAssertEqual(result.cleanableBytes(), 0)
        XCTAssertEqual(result.results[.devCaches]?.state, .missing)
        XCTAssertEqual(result.results[.projectArtifacts]?.state, .missing)
        XCTAssertEqual(result.results[.trash]?.state, .missing)
    }

    // MARK: Model

    @MainActor
    func testModelAdoptsDefaultSelectionAndTogglesAndRemovesDeleted() throws {
        try populate()
        let result = scanAll()
        let model = SmartScanModel(home: home, folderStore: ProjectFoldersStore(defaults: UserDefaults(suiteName: "smartscan-\(UUID().uuidString)")!, home: home))
        model.adopt(result, now: now)
        XCTAssertTrue(model.hasScanned)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(model.selection.isEmpty)
        XCTAssertLessThan(model.selectedBytes, model.foundBytes)
        let fresh = try XCTUnwrap(model.items(for: .projectArtifacts).first { SmartScanPresentation.projectName($0) == "fresh-web" })
        XCTAssertFalse(model.isSelected(fresh))
        model.toggle(fresh)
        XCTAssertTrue(model.isSelected(fresh))
        model.toggleAll(.projectArtifacts)
        XCTAssertEqual(model.selectedCount(for: .projectArtifacts), 0)
        model.toggleAll(.projectArtifacts)
        XCTAssertEqual(model.selectedCount(for: .projectArtifacts), model.items(for: .projectArtifacts).count)

        // Silme sonucu: taşınan öğe listeden ve seçimden kalkar, özet boyutu verir.
        let moved = try XCTUnwrap(model.items(for: .appCaches).first)
        let candidate = DeletionCandidate(item: moved, roots: CleanupCatalog.roots(home: home, ownBundleID: nil))
        model.deleteFinished([CleanupResult(candidate: candidate, outcome: .trashed(to: nil))], mode: .trash)
        XCTAssertFalse(model.items(for: .appCaches).contains { $0.id == moved.id })
        XCTAssertFalse(model.selection.contains(moved.id))
        XCTAssertEqual(model.lastFreed?.count, 1)
        XCTAssertEqual(model.lastFreed?.bytes, moved.bytes)
    }

    @MainActor
    func testModelCancelWhileScanningKeepsCompletedStepsAndGoesIdle() throws {
        let model = SmartScanModel(home: home, folderStore: ProjectFoldersStore(defaults: UserDefaults(suiteName: "smartscan-\(UUID().uuidString)")!, home: home))
        model.phase = .scanning
        model.result.results[.appCaches] = SmartScanStepResult(step: .appCaches, state: .scanned)
        model.cancel()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.result.wasCancelled)
        XCTAssertNotNil(model.result.results[.appCaches])
        // Boştayken iptal bir şey yapmaz.
        model.cancel()
        XCTAssertEqual(model.phase, .idle)
    }
}
