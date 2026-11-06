import XCTest
@testable import Adalmon

final class FolderScannerTests: XCTestCase {
    private var root: URL!
    override func setUp() {
        root = FileManager.default.temporaryDirectory.appending(path: "scan-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func write(_ rel: String, bytes: Int) throws {
        let url = root.appending(path: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 4096) { data[i] = UInt8(truncatingIfNeeded: i / 4096 + 1) } // seyrek dosya olmasın
        try data.write(to: url)
    }

    func testSumsAllocatedSizeAndRecordsChildrenByDepth() throws {
        try write("a/one.bin", bytes: 3 * 1_048_576)
        try write("a/deep/two.bin", bytes: 2 * 1_048_576)
        try write("b/three.bin", bytes: 1_048_576)
        try write("tiny/x.txt", bytes: 10)
        let r = try XCTUnwrap(FolderScanner.scan(root: FolderScanRoot(path: root.path, maxDepth: 2), minRecordedBytes: 1_048_576))
        XCTAssertEqual(FolderScanner.defaultMinRecordedBytes, 10 << 20)
        let mb: UInt64 = 1_048_576
        XCTAssertGreaterThanOrEqual(r.totalBytes, 6 * mb)
        XCTAssertLessThan(r.totalBytes, 6 * mb + 200_000, "yalnızca blok yuvarlaması fazlası")
        XCTAssertEqual(r.files, 4)
        let paths = Dictionary(uniqueKeysWithValues: r.entries.map { ($0.path, $0) })
        XCTAssertEqual(paths[root.path]?.depth, 0)
        XCTAssertEqual(paths[root.path]?.bytes, r.totalBytes)
        XCTAssertNotNil(paths[root.path + "/a"])
        XCTAssertNotNil(paths[root.path + "/a/deep"])
        XCTAssertNil(paths[root.path + "/tiny"], "1 MB altı kaydedilmez")
        XCTAssertGreaterThanOrEqual(paths[root.path + "/a"]?.bytes ?? 0, 5 * mb)
    }

    func testHardlinksAreCountedOnce() throws {
        try write("src/big.bin", bytes: 4 * 1_048_576)
        let base = try XCTUnwrap(FolderScanner.scan(root: FolderScanRoot(path: root.path, maxDepth: 0)))
        try FileManager.default.createDirectory(at: root.appending(path: "links"), withIntermediateDirectories: true)
        for i in 0..<3 {
            XCTAssertEqual(link(root.appending(path: "src/big.bin").path, root.appending(path: "links/l\(i)").path), 0)
        }
        let withLinks = try XCTUnwrap(FolderScanner.scan(root: FolderScanRoot(path: root.path, maxDepth: 0)))
        XCTAssertEqual(withLinks.totalBytes, base.totalBytes, "3 ek sabit bağ boyutu artırmaz")
        XCTAssertEqual(withLinks.files, 4)
    }

    func testSkippedChildSymlinkAndMissingRoot() throws {
        try write("keep/k.bin", bytes: 1_048_576)
        try write("Mail/secret.bin", bytes: 5 * 1_048_576)
        try write("target/t.bin", bytes: 3 * 1_048_576)
        XCTAssertEqual(symlink(root.appending(path: "target").path, root.appending(path: "ln").path), 0)
        let plain = try XCTUnwrap(FolderScanner.scan(root: FolderScanRoot(path: root.path, maxDepth: 1), minRecordedBytes: 1))
        let skipping = try XCTUnwrap(FolderScanner.scan(root: FolderScanRoot(path: root.path, maxDepth: 1, skipChildNames: ["Mail"]), minRecordedBytes: 1))
        XCTAssertEqual(plain.totalBytes - skipping.totalBytes, 5 * 1_048_576, "atlanan klasör taranmaz")
        XCTAssertFalse(skipping.entries.contains { $0.path.hasSuffix("/Mail") })
        XCTAssertFalse(plain.entries.contains { $0.path.hasSuffix("/ln") }, "sembolik bağ izlenmez / ayrı klasör sayılmaz")
        XCTAssertNil(FolderScanner.scan(root: FolderScanRoot(path: root.path + "/yok", maxDepth: 1)))
    }

    func testCancellationReturnsPromptly() throws {
        try write("a/x.bin", bytes: 1_048_576)
        let r = FolderScanner.scan(root: FolderScanRoot(path: root.path, maxDepth: 1), isCancelled: { true })
        XCTAssertEqual(r?.totalBytes, 0)
    }

    func testWatchListNeverIncludesProtectedLocations() {
        let home = "/Users/test"
        let roots = FolderWatchList.roots(home: home).map(\.path)
        for forbidden in ["/Containers", "/Group Containers", "/Mail", "/Safari", "/Messages", "/Photos", "/Downloads", "/Desktop", "/Documents", ".Trash"] {
            XCTAssertFalse(roots.contains { $0.contains(forbidden) }, forbidden)
        }
        XCTAssertTrue(roots.contains(home + "/Library/Caches"))
        XCTAssertTrue(roots.contains(home + "/Library/Developer"))
        let support = FolderWatchList.roots(home: home).first { $0.path.hasSuffix("Application Support") }
        XCTAssertEqual(support?.skips("Containers"), true)
        XCTAssertEqual(support?.skips("com.apple.TCC"), true)
        XCTAssertEqual(support?.skips("com.apple.anything"), true)
        XCTAssertEqual(support?.skips("Code"), false)
        XCTAssertEqual(FolderWatchList.roots(home: home).first { $0.path.hasSuffix(".gradle") }?.everyHours, 6, "en ağır kök 6 saatte bir")
        XCTAssertEqual(FolderWatchList.roots(home: home).first { $0.path.hasSuffix(".npm") }?.everyHours, 3)
        XCTAssertEqual(FolderWatchList.roots(home: home).first { $0.path.hasSuffix("/Library/Caches") }?.everyHours, 1)
        XCTAssertEqual(FolderWatchList.displayPath(home + "/Library/Caches", home: home), "~/Library/Caches")
        XCTAssertEqual(FolderWatchList.displayPath("/opt/x", home: home), "/opt/x")
    }
}
