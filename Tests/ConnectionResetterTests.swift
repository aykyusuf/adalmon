import XCTest
@testable import Adalmon

final class ConnectionResetterTests: XCTestCase {
    private let chrome = "/Applications/Google Chrome.app"
    private let me: UInt32 = 501

    private func candidate(_ pid: Int32, _ path: String, uid: UInt32 = 501) -> ConnectionResetter.Candidate {
        .init(pid: pid, path: path, uid: uid)
    }

    private func targets(_ list: [ConnectionResetter.Candidate], _ key: String, own: Int32 = 1) -> [Int32] {
        ConnectionResetter.targetPIDs(in: list, appKey: key, ownPID: own, uid: me)
    }

    func testBundlePrefixMatchesHelpers() {
        let list = [
            candidate(10, chrome + "/Contents/MacOS/Google Chrome"),
            candidate(11, chrome + "/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"),
            candidate(12, "/Applications/Safari.app/Contents/MacOS/Safari"),
        ]
        XCTAssertEqual(targets(list, chrome), [10, 11])
    }

    func testBundleSiblingWithSharedPrefixIsNotMatched() {
        let list = [
            candidate(20, "/Applications/Google Chrome.app2/Contents/MacOS/Google Chrome"),
            candidate(21, "/Applications/Google Chrome.app.bak/x"),
            candidate(22, chrome),
        ]
        XCTAssertEqual(targets(list, chrome), [22])
        XCTAssertEqual(targets(list, chrome + "/"), [22], "sondaki / yok sayılmalı")
    }

    func testExecutableExactMatchOnly() {
        let list = [
            candidate(30, "/usr/local/bin/spoofdpi"),
            candidate(31, "/usr/local/bin/spoofdpi-helper"),
            candidate(32, "/usr/local/bin/spoofdpi/child"),
        ]
        XCTAssertEqual(targets(list, "/usr/local/bin/spoofdpi"), [30])
    }

    func testExcludesOwnPIDAndOtherUsers() {
        let list = [
            candidate(1, chrome + "/Contents/MacOS/Google Chrome"),
            candidate(40, chrome + "/Contents/MacOS/Google Chrome", uid: 0),
            candidate(41, chrome + "/Contents/MacOS/Google Chrome", uid: 502),
            candidate(42, chrome + "/Contents/MacOS/Google Chrome"),
        ]
        XCTAssertEqual(targets(list, chrome, own: 1), [42])
    }

    func testEmptyKeyMatchesNothing() {
        XCTAssertTrue(targets([candidate(50, "/bin/sleep")], "").isEmpty)
    }

    /// Soket açmayan canlı bir süreç: eşleşmeli ve çökmeden sonuç vermeli.
    func testLiveResetOnSleepProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }

        let pid = process.processIdentifier
        let result = ConnectionResetter.resetConnections(forApp: "/bin/sleep")
        XCTAssertTrue(result.matchedPIDs.contains(pid), "sleep süreci eşleşmeli")
        let handled = result.resetPIDs.contains(pid) || result.failedPIDs.contains { $0.pid == pid }
        XCTAssertTrue(handled, "sleep ya sıfırlanmalı ya da hata olarak raporlanmalı")
        XCTAssertTrue(result.isRunning)
        XCTAssertTrue(process.isRunning, "süreç ölmemeli")
    }

    func testNotRunningAppReportsNothing() {
        let result = ConnectionResetter.resetConnections(forApp: "/Applications/Adalmon-Yok.app")
        XCTAssertFalse(result.isRunning)
        XCTAssertFalse(result.needsRestart)
    }
}
