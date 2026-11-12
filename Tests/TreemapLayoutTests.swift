import XCTest
@testable import Adalmon

final class TreemapLayoutTests: XCTestCase {
    let bounds = CGRect(x: 10, y: 20, width: 600, height: 340)

    func items(_ values: [Double]) -> [TreemapItem] { values.enumerated().map { TreemapItem(id: "i\($0.offset)", value: $0.element) } }

    func assertValid(_ values: [Double], in bounds: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let input = items(values)
        let out = TreemapLayout.layout(input, in: bounds)
        let positive = input.filter { $0.value.isFinite && $0.value > 0 }
        XCTAssertEqual(out.count, positive.count, file: file, line: line)
        let total = positive.reduce(0) { $0 + $1.value }
        let area = Double(bounds.width * bounds.height)
        let byID = Dictionary(uniqueKeysWithValues: input.map { ($0.id, $0.value) })
        let eps: CGFloat = 0.001
        for r in out {
            let expected = byID[r.id]! / total * area
            let actual = Double(r.rect.width * r.rect.height)
            XCTAssertEqual(actual, expected, accuracy: expected * 0.01 + 0.0001, "alan orantılı olmalı", file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.rect.minX, bounds.minX - eps, file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.rect.minY, bounds.minY - eps, file: file, line: line)
            XCTAssertLessThanOrEqual(r.rect.maxX, bounds.maxX + eps, file: file, line: line)
            XCTAssertLessThanOrEqual(r.rect.maxY, bounds.maxY + eps, file: file, line: line)
        }
        for i in 0..<out.count {
            for j in (i + 1)..<max(i + 1, out.count) {
                let inter = out[i].rect.intersection(out[j].rect)
                let overlap = inter.isNull ? 0 : Double(inter.width * inter.height)
                XCTAssertLessThan(overlap, 0.01, "kutular çakışmamalı (\(i),\(j))", file: file, line: line)
            }
        }
        let covered = out.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        XCTAssertEqual(covered, area, accuracy: area * 0.001, "alan tamamen dolmalı", file: file, line: line)
    }

    func testProportionalNoOverlapWithinBounds() {
        assertValid([6, 6, 4, 3, 2, 2, 1], in: bounds)
        assertValid([100, 1, 1, 1, 1, 1, 1, 1, 1, 1], in: bounds)
        assertValid(Array(repeating: 5, count: 37), in: bounds)
        assertValid((1...80).map { Double($0 * $0) }, in: CGRect(x: 0, y: 0, width: 300, height: 900))
        assertValid([1e12, 5e11, 3e9, 7e6, 2e3], in: CGRect(x: 0, y: 0, width: 1000, height: 200))
    }

    func testRandomInputsStayValid() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<30 {
            let values = (0..<Int.random(in: 2...60, using: &generator)).map { _ in Double.random(in: 1...1_000_000, using: &generator) }
            assertValid(values, in: CGRect(x: 0, y: 0, width: Double.random(in: 80...900), height: Double.random(in: 80...700)))
        }
    }

    func testEmptyZeroAndInvalidInputs() {
        XCTAssertTrue(TreemapLayout.layout([], in: bounds).isEmpty)
        XCTAssertTrue(TreemapLayout.layout(items([0, 0]), in: bounds).isEmpty)
        XCTAssertTrue(TreemapLayout.layout(items([5]), in: .zero).isEmpty)
        let out = TreemapLayout.layout(items([0, -3, .nan, .infinity, 4, 4]), in: bounds)
        XCTAssertEqual(out.map(\.id).sorted(), ["i4", "i5"])
    }

    func testSingleItemFillsBounds() {
        let out = TreemapLayout.layout(items([42]), in: bounds)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].rect, bounds)
    }

    func testLargestFirstAndStableForTies() {
        let out = TreemapLayout.layout(items([1, 9, 5, 5]), in: bounds)
        XCTAssertEqual(out.map(\.id), ["i1", "i2", "i3", "i0"])
    }

    func testReasonableAspectRatios() {
        let out = TreemapLayout.layout(items([6, 6, 4, 3, 2, 2, 1]), in: CGRect(x: 0, y: 0, width: 600, height: 400))
        for r in out {
            let ratio = max(r.rect.width / r.rect.height, r.rect.height / r.rect.width)
            XCTAssertLessThan(ratio, 4, "squarified kutular çok ince olmamalı")
        }
    }

    // MARK: Tarayıcı

    func testScannerMeasuresChildrenSkipsSymlinksAndMarksLocked() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "lens-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base) }
        let home = try XCTUnwrap(CleanupDeleter.realPath({ try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true); return base.path }()))
        let fm = FileManager.default
        for dir in ["Big", "Small", "Documents", "Library/Containers", "Library/Caches"] {
            try fm.createDirectory(atPath: home + "/" + dir, withIntermediateDirectories: true)
        }
        try Data(repeating: 7, count: 500_000).write(to: URL(fileURLWithPath: home + "/Big/a.bin"))
        try Data(repeating: 7, count: 20_000).write(to: URL(fileURLWithPath: home + "/Small/b.bin"))
        try Data(repeating: 7, count: 100_000).write(to: URL(fileURLWithPath: home + "/loose.bin"))
        try fm.createSymbolicLink(atPath: home + "/link", withDestinationPath: home + "/Big")
        let docs = home + "/Documents"
        let probe = PathProbe { $0 == docs ? .denied : .ok }
        var scanner = SpaceLensScanner(home: home, probe: probe)
        scanner.minKeepBytes = 0
        let scan = scanner.scan(path: home)
        XCTAssertEqual(scan.state, .scanned)
        let byName = Dictionary(uniqueKeysWithValues: scan.nodes.map { ($0.name, $0) })
        XCTAssertNil(byName["link"], "sembolik bağ izlenmez")
        XCTAssertEqual(byName["Big"]?.kind, .folder)
        XCTAssertGreaterThanOrEqual(byName["Big"]?.bytes ?? 0, 500_000)
        XCTAssertEqual(byName["loose.bin"]?.kind, .file)
        XCTAssertEqual(byName["Documents"]?.kind, .locked(.filesAndFolders(.documents)))
        XCTAssertEqual(scan.nodes.first?.name, "Big", "büyükten küçüğe")
        let library = scanner.scan(path: home + "/Library")
        XCTAssertEqual(library.nodes.first { $0.name == "Containers" }?.kind, .skipped(.appData))
        XCTAssertEqual(library.nodes.first { $0.name == "Caches" }?.kind, .folder)
    }

    func testScannerReportsNoAccessAndCancel() throws {
        XCTAssertEqual(SpaceLensScanner().scan(path: "/private/var/nonexistent-\(UUID().uuidString)").state, .missing)
        let base = FileManager.default.temporaryDirectory.appending(path: "lens2-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base.appending(path: "d"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let scan = SpaceLensScanner(home: base.path).scan(path: base.path, isCancelled: { true })
        XCTAssertTrue(scan.cancelled)
    }

    func testSpaceNodeItemsAggregateTheTail() {
        let nodes = (0..<200).map { SpaceNode(path: "/x/\($0)", kind: .file, bytes: UInt64(200 - $0)) }
            + [SpaceNode(path: "/x/lock", kind: .locked(.fullDiskAccess), bytes: 0)]
        let items = TreemapCanvas.items(for: nodes)
        XCTAssertEqual(items.count, TreemapCanvas.maxBoxes + 1)
        XCTAssertEqual(items.last?.id, TreemapCanvas.otherID)
        XCTAssertFalse(items.contains { $0.id == "/x/lock" })
    }
}
