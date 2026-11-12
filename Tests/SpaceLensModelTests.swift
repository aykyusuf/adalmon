import Darwin
import XCTest
@testable import Adalmon

/// Sayaçlı tarayıcı: gerçek tarayıcıyı sarar, kaç kez ve hangi yollar için çağrıldığını kaydeder.
final class CountingSpaceScanner: SpaceTreeScanning, @unchecked Sendable {
    let inner: SpaceLensScanner
    private let lock = NSLock()
    private var paths: [String] = []

    init(_ inner: SpaceLensScanner) { self.inner = inner }

    var calls: [String] { lock.withLock { paths } }

    func scan(path: String, isCancelled: @escaping () -> Bool, progress: @escaping (Int, Int, String) -> Void) -> SpaceLensScan {
        lock.withLock { paths.append(path) }
        return inner.scan(path: path, isCancelled: isCancelled, progress: progress)
    }
}

/// İptal edilene kadar bekleyen tarayıcı.
final class BlockingSpaceScanner: SpaceTreeScanning, @unchecked Sendable {
    func scan(path: String, isCancelled: @escaping () -> Bool, progress: @escaping (Int, Int, String) -> Void) -> SpaceLensScan {
        let deadline = Date().addingTimeInterval(10)
        while !isCancelled(), Date() < deadline { usleep(5_000) }
        return SpaceLensScan(root: path, cancelled: true)
    }
}

@MainActor
final class SpaceLensModelTests: XCTestCase {
    var base: URL!
    var home: String!
    let fm = FileManager.default

    override func setUpWithError() throws {
        base = fm.temporaryDirectory.appending(path: "lensmodel-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        home = try XCTUnwrap(CleanupDeleter.realPath(base.path))
    }

    override func tearDownWithError() throws {
        // Kilitli klasörler silinebilsin.
        for dir in ["Locked", "A/sub/priv"] { chmod(home + "/" + dir, 0o755) }
        try? fm.removeItem(at: base)
    }

    func write(_ rel: String, bytes: Int) throws {
        let url = URL(fileURLWithPath: home + "/" + rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: bytes).write(to: url)
    }

    /// Diskte ayrılan boyut (tarayıcıyla aynı ölçü: st_blocks * 512).
    func allocated(_ rel: String) -> UInt64 {
        var st = stat()
        XCTAssertEqual(lstat(home + "/" + rel, &st), 0, rel)
        return UInt64(st.st_blocks) * 512
    }

    /// A (3 MB + sub 2 MB + tiny 10 KB), B (1,5 MB), 2 MB dosya, 4 KB dosya.
    func makeFixture() throws {
        try write("A/big.bin", bytes: 3 << 20)
        try write("A/sub/deep.bin", bytes: 2 << 20)
        try write("A/tiny/t.bin", bytes: 10_000)
        try write("B/b.bin", bytes: 1_500_000)
        try write("loose.bin", bytes: 2 << 20)
        try write("small.bin", bytes: 4_000)
    }

    var fixtureTotal: UInt64 {
        ["A/big.bin", "A/sub/deep.bin", "A/tiny/t.bin", "B/b.bin", "loose.bin", "small.bin"].reduce(0) { $0 + allocated($1) }
    }

    func makeModel(scanner configure: (inout SpaceLensScanner) -> Void = { _ in }) -> (SpaceLensModel, CountingSpaceScanner) {
        var scanner = SpaceLensScanner(home: home)
        configure(&scanner)
        let counting = CountingSpaceScanner(scanner)
        return (SpaceLensModel(home: home, scanner: counting), counting)
    }

    // MARK: Tarayıcı: tek geçiş ağacı

    func testSinglePassBuildsTreeWithCorrectTotals() throws {
        try makeFixture()
        let scan = SpaceLensScanner(home: home).scan(path: home)
        XCTAssertEqual(scan.state, .scanned)
        let root = try XCTUnwrap(scan.dirs[home])
        XCTAssertEqual(root.totalBytes, fixtureTotal, "kökün toplamı tüm dosyaların toplamı")
        XCTAssertEqual(root.nodes.map(\.name), ["A", "loose.bin", "B"], "büyükten küçüğe, küçük dosya tek tek tutulmaz")
        XCTAssertEqual(root.otherBytes, allocated("small.bin"))
        XCTAssertEqual(root.otherCount, 1)

        let a = try XCTUnwrap(scan.dirs[home + "/A"], "alt klasörler aynı geçişte hazır")
        XCTAssertEqual(a.totalBytes, allocated("A/big.bin") + allocated("A/sub/deep.bin") + allocated("A/tiny/t.bin"))
        XCTAssertEqual(root.nodes.first { $0.name == "A" }?.bytes, a.totalBytes)
        XCTAssertEqual(scan.dirs[home + "/A/sub"]?.totalBytes, allocated("A/sub/deep.bin"))
        XCTAssertNil(scan.dirs[home + "/A/tiny"], "1 MB altı klasör kaydı tutulmaz")
        XCTAssertEqual(a.otherBytes, allocated("A/tiny/t.bin"), "küçük klasör 'diğer'de birleşir")
    }

    func testChildCapFoldsTheTailIntoOther() throws {
        try makeFixture()
        var scanner = SpaceLensScanner(home: home)
        scanner.maxChildren = 1
        let scan = scanner.scan(path: home)
        let root = try XCTUnwrap(scan.dirs[home])
        XCTAssertEqual(root.nodes.count, 1)
        XCTAssertEqual(root.totalBytes, fixtureTotal, "toplam korunur")
        XCTAssertEqual(root.otherCount, 3)
    }

    func testNodeCeilingLeavesDeepLevelsLazy() throws {
        try makeFixture()
        var scanner = SpaceLensScanner(home: home)
        scanner.maxStoredNodes = 1
        let scan = scanner.scan(path: home)
        XCTAssertNotNil(scan.dirs[home])
        XCTAssertNotNil(scan.dirs[home + "/A"], "ilk seviye her zaman kalır")
        XCTAssertNil(scan.dirs[home + "/A/sub"], "tavan aşılınca derin seviye tembel")
        XCTAssertTrue(scan.dirs[home]!.nodes.contains { $0.name == "A" && $0.isFolder })
    }

    func testUnreadableFoldersAreLockedAtAnyDepth() throws {
        try makeFixture()
        try fm.createDirectory(atPath: home + "/Locked", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: home + "/A/sub/priv", withIntermediateDirectories: true)
        chmod(home + "/Locked", 0o000)
        chmod(home + "/A/sub/priv", 0o000)
        let scan = SpaceLensScanner(home: home).scan(path: home)
        XCTAssertEqual(scan.dirs[home]?.nodes.first { $0.name == "Locked" }?.kind.isLocked, true)
        XCTAssertEqual(scan.dirs[home + "/A/sub"]?.nodes.first { $0.name == "priv" }?.kind.isLocked, true, "derin erişimsiz klasör kilitli kutu")
        XCTAssertEqual(scan.dirs[home]?.totalBytes, fixtureTotal)
    }

    // MARK: Model: önbellekten anında

    func testDrillDownAndBackUseCacheWithoutRescanning() async throws {
        try makeFixture()
        let (vm, counting) = makeModel()
        vm.start(root: home)
        XCTAssertEqual(vm.phase, .scanning)
        await vm.waitUntilIdle()
        XCTAssertEqual(counting.calls, [home])
        XCTAssertEqual(vm.totalBytes, fixtureTotal)

        vm.open(home + "/A")
        XCTAssertEqual(vm.phase, .idle, "önbellekten: tarama fazı yok")
        XCTAssertEqual(vm.current, home + "/A")
        XCTAssertFalse(vm.nodes.isEmpty)
        vm.open(home + "/A/sub")
        XCTAssertEqual(vm.current, home + "/A/sub")
        XCTAssertEqual(vm.nodes.map(\.name), ["deep.bin"])
        vm.back()
        XCTAssertEqual(vm.current, home + "/A")
        vm.go(to: 0)
        XCTAssertEqual(vm.current, home)
        XCTAssertEqual(vm.totalBytes, fixtureTotal)
        await vm.waitUntilIdle()
        XCTAssertEqual(counting.calls, [home], "gezinme tarayıcıyı tekrar çağırmaz")
    }

    func testRescanDropsCacheAndPicksUpChanges() async throws {
        try makeFixture()
        let (vm, counting) = makeModel()
        vm.start(root: home)
        await vm.waitUntilIdle()
        vm.open(home + "/A")
        let before = vm.totalBytes
        let rootBefore = try XCTUnwrap(vm.cache[home]).totalBytes

        try write("A/new.bin", bytes: 4 << 20)
        vm.rescan()
        XCTAssertEqual(vm.phase, .scanning)
        XCTAssertNil(vm.cache[home + "/A/sub"], "alt ağaç önbelleği atıldı")
        await vm.waitUntilIdle()
        XCTAssertEqual(counting.calls, [home, home + "/A"], "yeniden tara yalnızca geçerli klasörü yürür")
        XCTAssertEqual(vm.current, home + "/A")
        XCTAssertEqual(vm.totalBytes, before + allocated("A/new.bin"))
        let rootAfter = try XCTUnwrap(vm.cache[home])
        XCTAssertEqual(rootAfter.totalBytes, rootBefore + allocated("A/new.bin"), "üst klasör boyutu düzeltildi")
        XCTAssertEqual(rootAfter.nodes.first { $0.name == "A" }?.bytes, vm.totalBytes)
        XCTAssertEqual(rootAfter.nodes.first?.name, "A")
    }

    func testStartScanIsFreshButNavigationIsNot() async throws {
        try makeFixture()
        let (vm, counting) = makeModel()
        vm.start(root: home)
        await vm.waitUntilIdle()
        try write("B/more.bin", bytes: 3 << 20)
        vm.start(root: home)
        await vm.waitUntilIdle()
        XCTAssertEqual(counting.calls, [home, home])
        XCTAssertEqual(vm.totalBytes, fixtureTotal + allocated("B/more.bin"))
    }

    func testCancelStopsScanAndLeavesNothingCached() async throws {
        let vm = SpaceLensModel(home: home, scanner: BlockingSpaceScanner())
        vm.start(root: home)
        XCTAssertEqual(vm.phase, .scanning)
        vm.cancel()
        XCTAssertEqual(vm.phase, .idle)
        await vm.waitUntilIdle()
        XCTAssertTrue(vm.cache.isEmpty)
        XCTAssertTrue(vm.trail.isEmpty)
    }

    func testRealScannerHonoursCancellation() throws {
        try makeFixture()
        let scan = SpaceLensScanner(home: home).scan(path: home, isCancelled: { true })
        XCTAssertTrue(scan.cancelled)
        XCTAssertTrue(scan.dirs.isEmpty)
    }

    // MARK: Tembel seviyeler ve önceden hazırlama

    func testLazyLevelIsScannedOnDemandWhenNotVisible() async throws {
        try makeFixture()
        let (vm, counting) = makeModel { $0.maxStoredNodes = 1 }
        vm.start(root: home)
        await vm.waitUntilIdle()
        vm.open(home + "/A")
        XCTAssertEqual(vm.current, home + "/A")
        await vm.waitUntilIdle()
        XCTAssertEqual(counting.calls, [home], "görünür değilken önceden hazırlama yok")
        vm.open(home + "/A/sub")
        XCTAssertEqual(vm.phase, .scanning, "tembel seviye tıklanınca taranır")
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.current, home + "/A/sub")
        XCTAssertEqual(counting.calls, [home, home + "/A/sub"])
    }

    func testVisiblePagePrefetchesNextLevelSoClickIsInstant() async throws {
        try makeFixture()
        let (vm, counting) = makeModel { $0.maxStoredNodes = 1 }
        vm.setVisible(true)
        vm.start(root: home)
        await vm.waitUntilIdle()
        vm.open(home + "/A")
        await vm.waitUntilIdle() // A'nın tembel alt klasörü arka planda hazırlanır
        XCTAssertEqual(counting.calls, [home, home + "/A/sub"])
        vm.open(home + "/A/sub")
        XCTAssertEqual(vm.phase, .idle, "hazırlanmış seviye anında açılır")
        XCTAssertEqual(vm.current, home + "/A/sub")
        await vm.waitUntilIdle()
        XCTAssertEqual(counting.calls, [home, home + "/A/sub"], "tek seviye; fazladan tarama yok")
    }

    func testHidingThePageStopsPrefetch() async throws {
        try makeFixture()
        let (vm, counting) = makeModel { $0.maxStoredNodes = 1 }
        vm.start(root: home)
        await vm.waitUntilIdle()
        vm.setVisible(true)
        vm.setVisible(false)
        vm.open(home + "/A")
        await vm.waitUntilIdle()
        XCTAssertEqual(counting.calls, [home])
    }

    func testCacheEvictionKeepsTheTrail() async throws {
        try makeFixture()
        var scanner = SpaceLensScanner(home: home)
        scanner.maxStoredNodes = 1_000
        let counting = CountingSpaceScanner(scanner)
        let vm = SpaceLensModel(home: home, scanner: counting, cacheNodeLimit: 1)
        vm.start(root: home)
        await vm.waitUntilIdle()
        XCTAssertEqual(Set(vm.cache.keys), [home], "tavan aşıldı: yalnızca geçerli yol kalır")
        vm.open(home + "/A")
        await vm.waitUntilIdle()
        XCTAssertEqual(vm.current, home + "/A")
        vm.back()
        XCTAssertFalse(vm.nodes.isEmpty, "üst klasör önbellekte kalır")
    }
}

private extension SpaceNode.Kind {
    var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }
}
