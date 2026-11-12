import XCTest
@testable import Adalmon

final class SingleInstanceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "adalmon-lock-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testOnlyHigherPIDYields() {
        XCTAssertNil(SingleInstance.pick(otherPIDs: [], myPID: 100))
        XCTAssertEqual(SingleInstance.pick(otherPIDs: [90], myPID: 100), 90, "eski kopya varsa yeni çıkar")
        XCTAssertNil(SingleInstance.pick(otherPIDs: [110], myPID: 100), "ben daha eskiysem kalırım")
        XCTAssertEqual(SingleInstance.pick(otherPIDs: [120, 95, 80], myPID: 100), 80)
    }

    func testSecondLockOnSameFileFailsUntilFirstReleased() throws {
        let url = SingleInstance.lockFileURL(bundleURL: URL(filePath: "/Applications/Adalmon.app"), directory: dir)
        let first = try XCTUnwrap(SingleInstance.Lock.acquire(at: url))
        XCTAssertNil(SingleInstance.Lock.acquire(at: url), "ikinci kopya kilidi alamaz (ayrı fd, aynı dosya)")
        XCTAssertNil(SingleInstance.Lock.acquire(at: url), "yeniden deneme de başarısız")
        first.release()
        let again = SingleInstance.Lock.acquire(at: url)
        XCTAssertNotNil(again, "ilk kopya ölünce (fd kapanınca) kilit kalkar")
        again?.release()
    }

    func testLockReleasedWhenHolderDeallocates() throws {
        let url = SingleInstance.lockFileURL(bundleURL: URL(filePath: "/Applications/Adalmon.app"), directory: dir)
        var holder: SingleInstance.Lock? = try XCTUnwrap(SingleInstance.Lock.acquire(at: url))
        XCTAssertNil(SingleInstance.Lock.acquire(at: url))
        holder = nil
        let next = SingleInstance.Lock.acquire(at: url)
        XCTAssertNotNil(next)
        next?.release()
        _ = holder
    }

    func testLockIsNotInheritedByChildProcess() throws {
        let url = SingleInstance.lockFileURL(bundleURL: URL(filePath: "/Applications/Adalmon.app"), directory: dir)
        let holder = try XCTUnwrap(SingleInstance.Lock.acquire(at: url))
        let child = Process()
        child.executableURL = URL(filePath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { child.terminate(); child.waitUntilExit() }
        holder.release()
        let next = SingleInstance.Lock.acquire(at: url)
        XCTAssertNotNil(next, "çocuk süreç kilidi miras alıp tutmamalı (O_CLOEXEC)")
        next?.release()
    }

    func testDifferentBundlePathsUseDifferentLocks() throws {
        let installed = SingleInstance.lockFileURL(bundleURL: URL(filePath: "/Applications/Adalmon.app"), directory: dir)
        let debug = SingleInstance.lockFileURL(bundleURL: URL(filePath: "/private/tmp/dd/Build/Products/Debug/Adalmon.app"), directory: dir)
        XCTAssertNotEqual(installed, debug)
        XCTAssertTrue(installed.lastPathComponent.hasPrefix("instance-") && installed.lastPathComponent.hasSuffix(".lock"))
        XCTAssertEqual(installed, SingleInstance.lockFileURL(bundleURL: URL(filePath: "/Applications/./Adalmon.app"), directory: dir), "standartlaştırılmış yol aynı kilit")
        let a = try XCTUnwrap(SingleInstance.Lock.acquire(at: installed))
        let b = SingleInstance.Lock.acquire(at: debug)
        XCTAssertNotNil(b, "Debug/test kopyası kurulu kopyanın kilidini engellemez")
        a.release(); b?.release()
    }

    func testOnlySameBundlePathCounts() {
        let installed = URL(filePath: "/Applications/Adalmon.app")
        XCTAssertTrue(SingleInstance.isSameBundle(URL(filePath: "/Applications/Adalmon.app/"), installed))
        XCTAssertTrue(SingleInstance.isSameBundle(URL(filePath: "/Applications/../Applications/Adalmon.app"), installed))
        XCTAssertFalse(SingleInstance.isSameBundle(URL(filePath: "/private/tmp/dd/Build/Products/Debug/Adalmon.app"), installed), "DerivedData kopyası sayılmaz")
        XCTAssertFalse(SingleInstance.isSameBundle(nil, installed))
    }

    func testRunningTestHostIsNotCountedAgainstInstalledPath() {
        // Bu test süreci Debug/DerivedData kopyasıdır; /Applications yolu için yok sayılmalıdır.
        let others = SingleInstance.sameBundleApps(bundleURL: URL(filePath: "/Applications/Adalmon.app"),
                                                   bundleID: Bundle.main.bundleIdentifier, myPID: 1)
        XCTAssertFalse(others.contains { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier })
    }

    func testClaimYieldsToHolderOfSameBundleLockButNotToOtherPath() {
        let installed = URL(filePath: "/Applications/Adalmon.app")
        let debug = URL(filePath: "/private/tmp/dd-claim-test/Adalmon.app")
        // Sahte bundle kimliği: gerçek çalışan uygulamalarla eşleşmez, yalnızca kilit yolu sınanır.
        let id = "test.adalmon.claim.\(UUID().uuidString)"
        guard case .proceed = SingleInstance.claim(bundleURL: installed, bundleID: id, myPID: 1, lockDirectory: dir) else { return XCTFail("ilk kopya devam eder") }
        if case .proceed = SingleInstance.claim(bundleURL: installed, bundleID: id, myPID: 2, lockDirectory: dir) { XCTFail("aynı yoldaki ikinci kopya çıkmalı") }
        if case .yield = SingleInstance.claim(bundleURL: debug, bundleID: id, myPID: 3, lockDirectory: dir) { XCTFail("farklı yoldaki kopya engellenmemeli") }
    }

    func testTestEnvironmentSkipsClaim() {
        XCTAssertTrue(AppEnvironment.isRunningTests, "testte tek kopya denetimi çalışmaz (main() isRunningTests ile atlar)")
    }
}
