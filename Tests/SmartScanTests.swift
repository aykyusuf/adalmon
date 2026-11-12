import XCTest
@testable import Adalmon

/// Tüm testler geçici bir sahte ev klasöründe çalışır; gerçek ev klasörlerine dokunmaz.
final class SmartScanTests: XCTestCase {
    private var fixture: URL!
    private var home: String { fixture.path }
    private let mb = 1_048_576

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

    /// Güvenli ve riskli türlerin hepsini içeren sahte ev.
    private func populate() throws {
        try write("Library/Caches/com.example.big/blob.bin", bytes: 3 * mb)
        try write("Library/Caches/com.example.running/blob.bin", bytes: 2 * mb)
        try write("Library/Caches/Google/Chrome/Default/blob.bin", bytes: 4 * mb)
        try write("Library/Developer/Xcode/DerivedData/App-abc/blob.bin", bytes: 5 * mb)
        try write("Library/Developer/CoreSimulator/Caches/dyld/blob.bin", bytes: 2 * mb)
        try write(".Trash/old.bin", bytes: 6 * mb)
        // Riskli türler: taranmamalı.
        try write("Downloads/huge.dmg", bytes: 120 * mb)
        try write("Library/Application Support/MobileSync/Backup/dev1/blob.bin", bytes: 3 * mb)
        try write("Library/Logs/App/log.bin", bytes: 2 * mb)
        try write("Library/Developer/Xcode/Archives/2026/a.xcarchive/blob.bin", bytes: 2 * mb)
        try write("Library/Developer/Xcode/iOS DeviceSupport/17.0/blob.bin", bytes: 2 * mb)
    }

    private func scanAll(running: Set<String> = [], isCancelled: @escaping () -> Bool = { false },
                     stepFinished: @escaping (SmartScanStepResult) -> Void = { _ in }) -> SmartScanResult {
        SmartScanAggregator.run(home: home, runningBundleIDs: running, ownBundleID: nil,
                                isCancelled: isCancelled, stepFinished: stepFinished)
    }

    func testAggregatesSafeStepsOverFixtureHome() throws {
        try populate()
        let result = scanAll()
        XCTAssertFalse(result.wasCancelled)
        XCTAssertEqual(result.completed, SmartScanStep.allCases)
        XCTAssertTrue(result.notRun.isEmpty)

        let app = try XCTUnwrap(result.results[.appCaches])
        XCTAssertEqual(app.state, .scanned)
        XCTAssertEqual(Set(app.items.map(\.name)), ["com.example.big", "com.example.running"])
        XCTAssertGreaterThanOrEqual(app.cleanableBytes, UInt64(5 * mb))

        XCTAssertEqual(result.results[.browserCaches]?.items.count, 1)
        XCTAssertEqual(result.results[.devCaches]?.items.count, 2)
        XCTAssertGreaterThanOrEqual(result.results[.trash]?.trashBytes ?? 0, UInt64(6 * mb))
        XCTAssertEqual(result.results[.trash]?.state, .scanned)
        XCTAssertTrue(result.results[.trash]?.items.isEmpty ?? false)

        // Toplam = temizlenebilir adımların toplamı; Çöp Sepeti sayılmaz.
        let expected = SmartScanStep.allCases.filter(\.isCleanable).reduce(UInt64(0)) { $0 + (result.results[$1]?.cleanableBytes ?? 0) }
        XCTAssertEqual(result.cleanableBytes(), expected)
        XCTAssertGreaterThanOrEqual(result.cleanableBytes(), UInt64(16 * mb))
    }

    func testRiskyKindsAreNeverScannedOrSelected() throws {
        try populate()
        let result = scanAll()
        let risky: Set<CleanupCategory> = [.archives, .deviceSupport, .iosBackups, .downloads, .logs, .projectArtifacts]
        let items = result.results.values.flatMap(\.items)
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { !risky.contains($0.category) }, "riskli kategori taranmamalı")
        XCTAssertTrue(items.allSatisfy { $0.category.defaultSelected }, "yalnızca varsayılan seçili güvenli kategoriler")
        XCTAssertTrue(SmartScanAggregator.scannedCategories.isDisjoint(with: risky))
        for category in SmartScanAggregator.scannedCategories where category != .trash {
            XCTAssertFalse(category.needsExplicitScan, "\(category) kendi düğmesi gerektirir")
        }
        // Silme adaylarında da riskli tür yok; hepsi güvenli çekirdek türlerinden.
        let roots = CleanupCatalog.roots(home: home, ownBundleID: nil)
        let candidates = result.deletionCandidates(roots: roots)
        let safeKinds = Set(SmartScanAggregator.scannedCategories.map(\.kind))
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { safeKinds.contains($0.kind) })
        XCTAssertTrue(candidates.allSatisfy { !$0.path.contains("/Downloads/") && !$0.path.contains("MobileSync") })
        // Riskli türlerin yalnızca "İncele" kartı vardır; adım listesinde yoklar.
        XCTAssertEqual(Set(SmartScanReviewKind.allCases.map(\.rawValue)), ["orphans", "largeOld", "duplicates", "privacy", "projectArtifacts"])
        XCTAssertTrue(SmartScanReviewKind.allCases.allSatisfy { !SmartScanStep.allCases.map(\.subsection).isEmpty && $0.subsection != .smartScan })
    }

    func testRunningBrowserAndAppAreExcludedFromCleanable() throws {
        try populate()
        let result = scanAll(running: ["com.google.Chrome", "com.example.running"])
        let browser = try XCTUnwrap(result.results[.browserCaches])
        XCTAssertEqual(browser.runningBrowsers, ["Google Chrome"])
        XCTAssertEqual(browser.cleanableItems.count, 0)
        XCTAssertEqual(browser.cleanableBytes, 0)
        XCTAssertGreaterThan(browser.blockedBytes, 0)

        let app = try XCTUnwrap(result.results[.appCaches])
        XCTAssertEqual(app.cleanableItems.map(\.name), ["com.example.big"])
        XCTAssertEqual(app.blockedItems.map(\.name), ["com.example.running"])
        let candidates = result.deletionCandidates(roots: CleanupCatalog.roots(home: home, ownBundleID: nil))
        XCTAssertFalse(candidates.contains { $0.name == "com.example.running" })
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
        XCTAssertNotNil(result.results[.appCaches])
        XCTAssertNil(result.results[.browserCaches])
        XCTAssertNil(result.results[.devCaches])
        XCTAssertNil(result.results[.trash])
        XCTAssertEqual(result.notRun, [.browserCaches, .devCaches, .trash])
    }

    func testStepsRunInOrderAndReportProgress() throws {
        try populate()
        var started: [SmartScanStep] = []
        _ = SmartScanAggregator.run(home: home, runningBundleIDs: [], ownBundleID: nil, stepStarted: { started.append($0) })
        XCTAssertEqual(started, [.appCaches, .browserCaches, .devCaches, .trash])
    }

    func testEmptyHomeReportsMissingAndZero() {
        let result = scanAll()
        XCTAssertEqual(result.completed, SmartScanStep.allCases)
        XCTAssertEqual(result.cleanableBytes(), 0)
        XCTAssertEqual(result.results[.devCaches]?.state, .missing)
        XCTAssertEqual(result.results[.trash]?.state, .missing)
    }

    func testDisabledStepsAreLeftOutOfSelection() throws {
        try populate()
        let result = scanAll()
        let onlyApp = result.cleanableItems(steps: [.appCaches])
        XCTAssertTrue(onlyApp.allSatisfy { $0.category == .appCaches })
        XCTAssertTrue(result.cleanableItems(steps: [.trash]).isEmpty)
        XCTAssertLessThan(result.cleanableBytes(steps: [.appCaches]), result.cleanableBytes())
    }
}
