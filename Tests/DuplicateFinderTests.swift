import CryptoKit
import XCTest
@testable import Adalmon

final class DuplicateFinderTests: XCTestCase {
    var root: String!

    override func setUpWithError() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "dups-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = CleanupDeleter.realPath(url.path)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: root) }

    @discardableResult
    func write(_ rel: String, bytes: Int, seed: UInt8 = 1, tweakLast: UInt8? = nil) throws -> String {
        let path = root + "/" + rel
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        var data = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 1024) { data[i] = seed &+ UInt8(truncatingIfNeeded: i / 1024) }
        if let tweakLast { data[bytes - 1] = tweakLast }
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    func finder(minBytes: UInt64 = 100 * 1024, stat: StatProvider = .live) -> DuplicateFinder {
        DuplicateFinder(minBytes: minBytes, stat: stat)
    }

    func testEqualSizeDifferentContentIsNotGrouped() throws {
        try write("a.bin", bytes: 300_000, seed: 1)
        try write("b.bin", bytes: 300_000, seed: 2)
        XCTAssertTrue(finder().find(roots: [root]).groups.isEmpty)
    }

    func testSamePrefixButDifferentTailIsNotGrouped() throws {
        // İlk 64 KB aynı, son bayt farklı: yalnızca tam özet ayırt eder.
        try write("a.bin", bytes: 300_000, seed: 1, tweakLast: 1)
        try write("b.bin", bytes: 300_000, seed: 1, tweakLast: 2)
        XCTAssertTrue(finder().find(roots: [root]).groups.isEmpty)
    }

    func testIdenticalContentFormsOneGroupWithOldestKept() throws {
        let a = try write("z/copy.bin", bytes: 300_000, seed: 3)
        let b = try write("a.bin", bytes: 300_000, seed: 3)
        let c = try write("deep/er/c.bin", bytes: 300_000, seed: 3)
        try write("other.bin", bytes: 300_000, seed: 4)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: c)
        let result = finder().find(roots: [root])
        XCTAssertEqual(result.groups.count, 1)
        let group = try XCTUnwrap(result.groups.first)
        XCTAssertEqual(Set(group.files.map(\.path)), [a, b, c])
        XCTAssertEqual(group.defaultKeeper.path, c, "en eski korunur")
        XCTAssertEqual(group.size, 300_000)
        XCTAssertGreaterThan(group.reclaimableBytes, 0)
    }

    func testTieBreaksOnShortestPath() throws {
        let a = try write("long/dir/name/x.bin", bytes: 200_000, seed: 3)
        let b = try write("y.bin", bytes: 200_000, seed: 3)
        let date = Date(timeIntervalSince1970: 2_000_000)
        for p in [a, b] { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: p) }
        XCTAssertEqual(finder().find(roots: [root]).groups.first?.defaultKeeper.path, b)
    }

    func testSmallFilesUnderPrefixSizeAreStillMatched() throws {
        try write("a.bin", bytes: 10_000, seed: 3)
        try write("b.bin", bytes: 10_000, seed: 3)
        try write("c.bin", bytes: 10_000, seed: 4)
        let groups = finder(minBytes: 1000).find(roots: [root]).groups
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.count, 2)
    }

    func testBelowMinimumSizeIgnored() throws {
        try write("a.bin", bytes: 10_000, seed: 3)
        try write("b.bin", bytes: 10_000, seed: 3)
        XCTAssertTrue(finder().find(roots: [root]).groups.isEmpty)
    }

    func testSymlinkNotFollowedAndNotCountedAsCopy() throws {
        let a = try write("a.bin", bytes: 200_000, seed: 3)
        try FileManager.default.createSymbolicLink(atPath: root + "/link.bin", withDestinationPath: a)
        XCTAssertTrue(finder().find(roots: [root]).groups.isEmpty)
    }

    func testHardlinkCountsOnce() throws {
        let a = try write("a.bin", bytes: 200_000, seed: 3)
        XCTAssertEqual(link(a, root + "/b.bin"), 0)
        XCTAssertTrue(finder().find(roots: [root]).groups.isEmpty, "aynı inode kopya değildir")
        try write("c.bin", bytes: 200_000, seed: 3)
        XCTAssertEqual(finder().find(roots: [root]).groups.first?.files.count, 2)
    }

    func testDatalessFileIsSkipped() throws {
        let a = try write("a.bin", bytes: 200_000, seed: 3)
        try write("b.bin", bytes: 200_000, seed: 3)
        let stat = StatProvider { path in
            guard var st = StatProvider.live.lstat(path) else { return nil }
            if path == a { st.flags |= FileStat.datalessFlag }
            return st
        }
        XCTAssertTrue(finder(stat: stat).find(roots: [root]).groups.isEmpty)
    }

    func testCancellation() throws {
        for i in 0..<10 { try write("f\(i).bin", bytes: 200_000, seed: 3) }
        var calls = 0
        let result = finder().find(roots: [root], isCancelled: { calls += 1; return calls > 4 })
        XCTAssertTrue(result.cancelled)
        XCTAssertTrue(result.groups.isEmpty)
    }

    func testHashMatchesCryptoKitAndHonoursLimit() throws {
        let path = try write("h.bin", bytes: 3_000_000, seed: 5)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard case .digest(let full) = DuplicateFinder.hash(path: path, expectedSize: 3_000_000, limit: nil, isCancelled: { false }) else { return XCTFail() }
        XCTAssertEqual(full, Data(SHA256.hash(data: data)))
        guard case .digest(let prefix) = DuplicateFinder.hash(path: path, expectedSize: 3_000_000, limit: 65_536, isCancelled: { false }) else { return XCTFail() }
        XCTAssertEqual(prefix, Data(SHA256.hash(data: data.prefix(65_536))))
        XCTAssertEqual(DuplicateFinder.hash(path: path, expectedSize: 1, limit: nil, isCancelled: { false }), .failed, "boyut değişmiş")
    }

    func testSelectionNeverSelectsWholeGroup() throws {
        for name in ["a", "b", "c"] { try write("\(name).bin", bytes: 200_000, seed: 3) }
        let groups = finder().find(roots: [root]).groups
        let group = try XCTUnwrap(groups.first)
        var selection = DuplicateSelection(groups: groups)
        XCTAssertTrue(selection.selected.isEmpty, "önceden seçili gelmez")
        selection.selectAllButKeepers(in: groups)
        XCTAssertEqual(selection.selected.count, 2)
        XCTAssertFalse(selection.toggle(group.defaultKeeper.path, in: group), "korunan seçilemez")
        XCTAssertFalse(selection.selected.contains(group.defaultKeeper.path))
        // Korunanı değiştirmek eski korunanı seçilebilir kılar, yenisini seçimden çıkarır.
        let other = group.files[1]
        selection.setKeeper(other.path, in: group)
        XCTAssertFalse(selection.selected.contains(other.path))
        XCTAssertTrue(selection.toggle(group.defaultKeeper.path, in: group))
        XCTAssertEqual(selection.selected.count, 2)
        XCTAssertLessThan(selection.selectedFiles(in: groups).count, group.files.count)
        XCTAssertFalse(selection.toggle("/nowhere", in: group))
    }

    func testVerifiedDeletionsRefuseWhenKeeperGoneOrFileChanged() throws {
        for name in ["a", "b", "c"] { try write("\(name).bin", bytes: 200_000, seed: 3) }
        let groups = finder().find(roots: [root]).groups
        let group = try XCTUnwrap(groups.first)
        var selection = DuplicateSelection(groups: groups)
        selection.selectAllButKeepers(in: groups)
        var check = selection.verifiedDeletions(in: groups)
        XCTAssertEqual(check.deletable.count, 2)
        XCTAssertTrue(check.refused.isEmpty)
        // Seçili bir dosya değişti.
        let changed = try XCTUnwrap(selection.selectedFiles(in: groups).first)
        try Data(count: 1234).write(to: URL(fileURLWithPath: changed.path))
        check = selection.verifiedDeletions(in: groups)
        XCTAssertEqual(check.deletable.count, 1)
        XCTAssertEqual(check.refused.count, 1)
        // Korunan dosya yok oldu: hiçbiri silinmez.
        try FileManager.default.removeItem(atPath: group.defaultKeeper.path)
        check = selection.verifiedDeletions(in: groups)
        XCTAssertTrue(check.deletable.isEmpty)
        XCTAssertEqual(check.refused.count, 2)
    }

    func testCandidateScopeIsDescendantOfChosenRoots() throws {
        let a = try write("a.bin", bytes: 200_000, seed: 3)
        try write("b.bin", bytes: 200_000, seed: 3)
        let file = try XCTUnwrap(finder().find(roots: [root]).groups.first?.files.first { $0.path == a })
        let candidate = file.candidate(roots: [root])
        XCTAssertEqual(candidate.kind, "files.duplicates")
        XCTAssertEqual(candidate.scope, .descendant(roots: [root], nameAllowlist: nil))
    }
}
