import Darwin
import XCTest
@testable import Adalmon

/// Yer kaplayanlar temizlik listesi: seçimden aday üretimi, kök/korunan konum reddi, silme sonrası önbellek güncellemesi.
/// Her şey geçici bir sahte ev klasöründe; Çöp'e taşıma fixture dışındaki sahte bir klasöre yapılır, günlük de orada tutulur.
@MainActor
final class SpaceLensDeletionTests: XCTestCase {
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var _trash: [String] = []
        private var _remove: [String] = []
        var trash: [String] { lock.withLock { _trash } }
        var remove: [String] { lock.withLock { _remove } }
        func addTrash(_ p: String) { lock.withLock { _trash.append(p) } }
        func addRemove(_ p: String) { lock.withLock { _remove.append(p) } }
    }

    private var base: URL!
    private var home: String!
    private var outside: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        base = fm.temporaryDirectory.appending(path: "lensdel-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        home = try XCTUnwrap(CleanupDeleter.realPath(base.path))
        outside = fm.temporaryDirectory.appending(path: "lensdel-out-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: outside.appending(path: "trash"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: base)
        try? fm.removeItem(at: outside)
    }

    private func write(_ rel: String, bytes: Int) throws {
        let url = URL(fileURLWithPath: home + "/" + rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: bytes).write(to: url)
    }

    /// A (big 3 MB + sub 2 MB), B (1,5 MB), loose 2 MB, Library/Foo (2 MB), Documents (2 MB).
    private func makeFixture() throws {
        try write("A/big.bin", bytes: 3 << 20)
        try write("A/sub/deep.bin", bytes: 2 << 20)
        try write("B/b.bin", bytes: 1_500_000)
        try write("loose.bin", bytes: 2 << 20)
        try write("Library/Foo/f.bin", bytes: 2 << 20)
        try write("Documents/d.bin", bytes: 2 << 20)
    }

    private func makeModel(identity: (@Sendable (String) -> (dev: Int32, ino: UInt64)?)? = nil)
        -> (model: SpaceLensModel, scanner: CountingSpaceScanner, calls: Calls) {
        let calls = Calls()
        let trash = outside.appending(path: "trash")
        let deleter = CleanupDeleter(
            home: home, runningBundleIDs: { [] }, logURL: outside.appending(path: "log.jsonl"), ownPaths: [],
            moveToTrash: { url in
                calls.addTrash(url.path)
                let dest = trash.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            removePermanently: { url in
                calls.addRemove(url.path)
                try FileManager.default.removeItem(at: url)
            })
        let counting = CountingSpaceScanner(SpaceLensScanner(home: home))
        let model = SpaceLensModel(home: home, scanner: counting, deleter: deleter, identity: identity ?? SpaceLensIdentity.live)
        return (model, counting, calls)
    }

    private func scanned() async throws -> (model: SpaceLensModel, scanner: CountingSpaceScanner, calls: Calls) {
        try makeFixture()
        let made = makeModel()
        made.model.start(root: home)
        await made.model.waitUntilIdle()
        XCTAssertEqual(made.model.current, home)
        return made
    }

    private func node(_ model: SpaceLensModel, _ name: String) throws -> SpaceNode {
        try XCTUnwrap(model.nodes.first { $0.name == name }, name)
    }

    // MARK: Seçim → aday

    func testSelectionBuildsDescendantCandidatesScopedToScanRoot() async throws {
        let (model, _, _) = try await scanned()
        let a = try node(model, "A")
        let loose = try node(model, "loose.bin")
        XCTAssertEqual(model.toggleMark(a), .marked)
        XCTAssertEqual(model.toggleMark(loose), .marked)
        let candidates = model.candidates()
        XCTAssertEqual(Set(candidates.map(\.path)), [home + "/A", home + "/loose.bin"])
        for candidate in candidates {
            XCTAssertEqual(candidate.scope, .descendant(roots: [home], nameAllowlist: nil))
            XCTAssertEqual(candidate.bytes, model.nodes.first { $0.path == candidate.path }?.bytes)
        }
        XCTAssertEqual(model.markedBytes, a.bytes + loose.bytes)
        XCTAssertEqual(model.toggleMark(loose), .unmarked)
        XCTAssertEqual(model.candidates().count, 1)
    }

    func testScanRootAndProtectedPathsAreNotSelectable() async throws {
        let (model, _, _) = try await scanned()
        let rootNode = SpaceNode(path: home, kind: .folder, bytes: 1 << 20)
        XCTAssertNotNil(model.markRefusal(for: rootNode), "tarama kökü seçilemez")
        XCTAssertEqual(model.toggleMark(rootNode), .blocked("Tarama kökünün kendisi seçilemez"))
        XCTAssertNotNil(model.markRefusal(for: try node(model, "Library")), "~/Library korunur")
        XCTAssertNotNil(model.markRefusal(for: try node(model, "Documents")), "~/Documents korunur")
        XCTAssertNil(model.markRefusal(for: try node(model, "A")))
        // ~/Library'nin doğrudan çocukları da korunur.
        model.open(home + "/Library")
        await model.waitUntilIdle()
        XCTAssertEqual(model.markRefusal(for: try node(model, "Foo")), "Korunan konum")
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertTrue(model.candidates().isEmpty)
        // Ölçülemeyen öğe seçilemez.
        XCTAssertNotNil(model.markRefusal(for: SpaceNode(path: home + "/Mail", kind: .skipped(.fullDiskAccess), bytes: 0)))
    }

    func testRootOutsideHomeAllowsNothing() async throws {
        let guardRules = SpaceLensGuard(root: "/usr/local", home: home)
        XCTAssertNotNil(guardRules.refusal(for: "/usr/local/foo"))
        let appsGuard = SpaceLensGuard(root: "/Applications", home: home)
        XCTAssertNotNil(appsGuard.refusal(for: "/Applications/Foo.app"))
    }

    func testNestedSelectionNeverDoubleCounts() async throws {
        let (model, _, _) = try await scanned()
        let a = try node(model, "A")
        model.open(home + "/A")
        let sub = try node(model, "sub")
        let big = try node(model, "big.bin")
        XCTAssertEqual(model.toggleMark(sub), .marked)
        model.go(to: 0)
        XCTAssertEqual(model.toggleMark(a), .marked, "üst klasör seçilince altındaki seçim düşer")
        XCTAssertFalse(model.isMarked(sub.path))
        XCTAssertEqual(model.selection.count, 1)
        XCTAssertEqual(model.markedBytes, a.bytes)
        model.open(home + "/A")
        XCTAssertEqual(model.toggleMark(big), .blocked("Üst klasör zaten seçili"))
        XCTAssertTrue(model.isCovered(big.path))
        XCTAssertEqual(model.markedBytes, a.bytes)
    }

    // MARK: Silme → önbellek

    func testDeleteUpdatesCachedTreeWithoutRescanning() async throws {
        let (model, scanner, calls) = try await scanned()
        model.open(home + "/A")
        let rootBefore = try XCTUnwrap(model.cache[home])
        let aBefore = try XCTUnwrap(model.cache[home + "/A"])
        let sub = try node(model, "sub")
        let scansBefore = scanner.calls.count

        XCTAssertEqual(model.toggleMark(sub), .marked)
        model.deleteMarked(mode: .trash)
        XCTAssertEqual(model.phase, .deleting)
        await model.waitUntilIdle()

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(calls.trash, [home + "/A/sub"])
        XCTAssertTrue(calls.remove.isEmpty, "varsayılan Çöp: kalıcı silme çağrılmaz")
        XCTAssertFalse(fm.fileExists(atPath: home + "/A/sub"))
        let freed = try XCTUnwrap(model.lastFreed)
        XCTAssertEqual(freed.count, 1)
        XCTAssertEqual(freed.bytes, sub.bytes)
        XCTAssertEqual(freed.skipped, 0)
        XCTAssertTrue(model.selection.isEmpty)

        let aAfter = try XCTUnwrap(model.cache[home + "/A"])
        XCTAssertFalse(aAfter.nodes.contains { $0.path == sub.path }, "silinen düğüm haritadan kalkar")
        XCTAssertEqual(aAfter.totalBytes, aBefore.totalBytes - sub.bytes, "klasör boyutu düşer")
        XCTAssertNil(model.cache[home + "/A/sub"], "silinen klasörün alt kaydı atılır")
        let rootAfter = try XCTUnwrap(model.cache[home])
        XCTAssertEqual(rootAfter.totalBytes, rootBefore.totalBytes - sub.bytes, "üst klasörün toplamı da düşer")
        XCTAssertEqual(rootAfter.nodes.first { $0.name == "A" }?.bytes, aAfter.totalBytes, "üstteki A karosu yeni boyutu gösterir")
        XCTAssertEqual(scanner.calls.count, scansBefore, "yeniden tarama yok")
        XCTAssertEqual(model.totalBytes, aAfter.totalBytes)
    }

    func testDeletingAFolderTheTrailPassesThroughTruncatesTrail() async throws {
        let (model, _, _) = try await scanned()
        XCTAssertEqual(model.toggleMark(try node(model, "A")), .marked)
        model.open(home + "/A")
        XCTAssertEqual(model.trail, [home, home + "/A"])
        model.deleteMarked(mode: .trash)
        await model.waitUntilIdle()
        XCTAssertEqual(model.trail, [home], "silinen klasörün içinde kalınmaz")
        XCTAssertFalse(model.nodes.contains { $0.name == "A" })
        XCTAssertNil(model.cache[home + "/A"])
    }

    func testPermanentModeUsesRemoveNotTrash() async throws {
        let (model, _, calls) = try await scanned()
        XCTAssertEqual(model.toggleMark(try node(model, "loose.bin")), .marked)
        model.deleteMarked(mode: .permanent)
        await model.waitUntilIdle()
        XCTAssertEqual(calls.remove, [home + "/loose.bin"])
        XCTAssertTrue(calls.trash.isEmpty)
        XCTAssertEqual(model.lastMode, .permanent)
        XCTAssertFalse(model.nodes.contains { $0.name == "loose.bin" })
    }

    func testRefusedItemsAreReportedAndTreeStaysUntouched() async throws {
        try makeFixture()
        // Kimlik yanlış: deleter "taramadan sonra değişmiş" diyerek reddeder.
        let (model, _, calls) = makeModel(identity: { _ in (dev: 1, ino: 1) })
        model.start(root: home)
        await model.waitUntilIdle()
        let before = model.cache[home]
        XCTAssertEqual(model.toggleMark(try node(model, "loose.bin")), .marked)
        model.deleteMarked(mode: .trash)
        await model.waitUntilIdle()
        XCTAssertTrue(calls.trash.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: home + "/loose.bin"))
        let freed = try XCTUnwrap(model.lastFreed)
        XCTAssertEqual(freed.count, 0)
        XCTAssertEqual(freed.skipped, 1)
        XCTAssertEqual(model.cache[home], before, "silinemeyen öğe haritada kalır")
    }

    func testNewScanClearsSelection() async throws {
        let (model, _, _) = try await scanned()
        XCTAssertEqual(model.toggleMark(try node(model, "A")), .marked)
        model.rescan()
        await model.waitUntilIdle()
        XCTAssertTrue(model.selection.isEmpty, "yeniden taramada seçim sıfırlanır")
    }
}
