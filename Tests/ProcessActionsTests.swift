import XCTest
@testable import Adalmon

/// Süreç eylemleri: izin kapıları (saf mantık) ve gerçek bir alt süreçte sinyal / öncelik / verimlilik yardımcıları.
@MainActor
final class ProcessActionsTests: XCTestCase {
    // MARK: Saf mantık

    func testPermissionGating() {
        let app = ProcessPermissions.evaluate(category: .app, key: "/Applications/Safari.app", isMember: false, ownedCount: 3, totalCount: 3)
        XCTAssertTrue(app.canControl)
        XCTAssertTrue(app.canRestart)
        XCTAssertTrue(app.canNetworkControl)
        XCTAssertNil(app.reason)

        let member = ProcessPermissions.evaluate(category: .app, key: "/Applications/Safari.app", isMember: true, ownedCount: 1, totalCount: 1)
        XCTAssertTrue(member.canControl)
        XCTAssertFalse(member.canRestart, "üye süreç uygulama gibi yeniden başlatılmaz")
        XCTAssertFalse(member.canNetworkControl, "ağ kontrolü uygulama düzeyindedir")

        let background = ProcessPermissions.evaluate(category: .background, key: "/opt/homebrew/bin/redis-server", isMember: false, ownedCount: 1, totalCount: 1)
        XCTAssertTrue(background.canControl)
        XCTAssertFalse(background.canRestart, ".app olmayan araç yeniden başlatılamaz")

        let system = ProcessPermissions.evaluate(category: .system, key: "/System/Library/CoreServices/loginwindow.app", isMember: false, ownedCount: 1, totalCount: 1)
        XCTAssertFalse(system.canControl, "kullanıcının uid'sinde çalışsa bile sistem kategorisi değiştirilemez")
        XCTAssertFalse(system.canNetworkControl)
        XCTAssertNotNil(system.reason)

        let bucket = ProcessPermissions.evaluate(category: .background, key: ResourceKeys.system, isMember: false, ownedCount: 9, totalCount: 9)
        XCTAssertFalse(bucket.canControl)

        let root = ProcessPermissions.evaluate(category: .background, key: "/usr/sbin/cupsd", isMember: false, ownedCount: 0, totalCount: 1)
        XCTAssertFalse(root.canControl)
        XCTAssertTrue(root.reason?.contains("root") ?? false)
        XCTAssertTrue(root.canRevealFile, "Finder'da göstermek izin gerektirmez")

        let gone = ProcessPermissions.evaluate(category: .app, key: "/Applications/X.app", isMember: false, ownedCount: 0, totalCount: 0)
        XCTAssertEqual(gone.reason, "Süreç artık çalışmıyor.")
    }

    func testPriorityPlanOnlyLowers() {
        XCTAssertEqual(ProcessPriorityPlan.evaluate(currentNice: 0, target: 10), .apply(10))
        XCTAssertEqual(ProcessPriorityPlan.evaluate(currentNice: 10, target: 10), .noChange)
        XCTAssertEqual(ProcessPriorityPlan.evaluate(currentNice: 10, target: 0), .needsRoot)
        XCTAssertEqual(ProcessPriorityPlan.evaluate(currentNice: 5, target: 19), .apply(19))
    }

    func testStateSummaryCountsOnlyOwnedProcesses() {
        XCTAssertEqual(ProcessStateSummary(items: []), ProcessStateSummary())
        let allStopped = ProcessStateSummary(items: [.init(isOwned: true, isStopped: true, isEfficient: false),
                                                     .init(isOwned: true, isStopped: true, isEfficient: false),
                                                     .init(isOwned: false, isStopped: false, isEfficient: false)])
        XCTAssertTrue(allStopped.isSuspended, "sahibi olmadığımız süreçler hesaba girmez")
        let mixed = ProcessStateSummary(items: [.init(isOwned: true, isStopped: true, isEfficient: true),
                                                .init(isOwned: true, isStopped: false, isEfficient: true)])
        XCTAssertFalse(mixed.isSuspended)
        XCTAssertTrue(mixed.isEfficient)
        XCTAssertEqual(ProcessStateSummary(items: [.init(isOwned: false, isStopped: true, isEfficient: true)]), ProcessStateSummary())
    }

    func testRowGatingThroughModel() {
        let live = ProcessLiveModel()
        let system = LiveRow(id: "s", key: "/System/Library/CoreServices/loginwindow.app", name: "loginwindow", pid: nil, processCount: 1,
                             pids: [getppid()], category: .system, path: nil, cpu: 0, memory: 0, gpu: 0, disk: 0, network: 0, energy: 0)
        XCTAssertFalse(live.canKill(system))
        live.requestKill(system)
        XCTAssertNil(live.killRequest)
        live.toggleSuspend(system) // sessizce reddedilir, sinyal gitmez
        XCTAssertNil(live.statusMessage)
    }

    // MARK: Gerçek alt süreç

    private func spawnSleeper() throws -> Process {
        let p = Process()
        p.executableURL = URL(filePath: "/bin/sleep")
        p.arguments = ["60"]
        try p.run()
        return p
    }

    func testSuspendResumeAndEfficiencyOnChildProcess() throws {
        let child = try spawnSleeper()
        defer { child.terminate() }
        let pid = child.processIdentifier
        XCTAssertTrue(ProcessActions.isKillable(pid: pid), "kendi kullanıcımızın alt süreci")
        XCTAssertEqual(ProcessActions.killablePIDs([pid, 1, getpid()]), [pid])

        XCTAssertFalse(ProcessActions.isStopped(pid: pid))
        XCTAssertEqual(ProcessActions.suspend([pid]), 1)
        XCTAssertTrue(waitUntil { ProcessActions.isStopped(pid: pid) })
        XCTAssertTrue(ProcessActions.state(of: [pid]).isSuspended)
        XCTAssertEqual(ProcessActions.resume([pid]), 1)
        XCTAssertTrue(waitUntil { !ProcessActions.isStopped(pid: pid) })
        XCTAssertFalse(ProcessActions.state(of: [pid]).isSuspended)

        XCTAssertFalse(ProcessActions.isEfficient(pid: pid))
        XCTAssertEqual(ProcessActions.setEfficiency([pid], on: true), 1)
        XCTAssertTrue(ProcessActions.isEfficient(pid: pid))
        XCTAssertTrue(ProcessActions.state(of: [pid]).isEfficient)
        XCTAssertEqual(ProcessActions.setEfficiency([pid], on: false), 1, "verimlilik modu geri alınabilir")
        XCTAssertFalse(ProcessActions.isEfficient(pid: pid))
    }

    func testNiceCanOnlyBeRaisedWithoutRoot() throws {
        let child = try spawnSleeper()
        defer { child.terminate() }
        let pid = child.processIdentifier
        XCTAssertEqual(ProcessActions.nice(of: pid), 0)
        XCTAssertEqual(ProcessActions.setNice([pid], to: 10), 1)
        XCTAssertEqual(ProcessActions.nice(of: pid), 10)
        XCTAssertEqual(ProcessActions.setNice([pid], to: 0), 0, "root olmadan öncelik artırılamaz")
        XCTAssertEqual(ProcessActions.nice(of: pid), 10)
    }

    func testTerminateAndForceKillChildProcess() throws {
        let nice = try spawnSleeper()
        XCTAssertEqual(ProcessActions.terminate([nice.processIdentifier]), 1)
        nice.waitUntilExit()
        XCTAssertEqual(nice.terminationReason, .uncaughtSignal)
        XCTAssertEqual(nice.terminationStatus, SIGTERM)

        let stubborn = try spawnSleeper()
        ProcessActions.suspend([stubborn.processIdentifier]) // SIGSTOP'lu süreç SIGTERM'e yanıt vermez
        ProcessActions.terminate([stubborn.processIdentifier])
        XCTAssertEqual(ProcessActions.alive(ProcessActions.killablePIDs([stubborn.processIdentifier])), [stubborn.processIdentifier], "askıdaki süreç hâlâ yaşar")
        XCTAssertEqual(ProcessActions.forceKill([stubborn.processIdentifier]), 1)
        stubborn.waitUntilExit()
        XCTAssertEqual(stubborn.terminationReason, .uncaughtSignal, "askıdaki süreç bekleyen SIGTERM / SIGKILL ile sonlanır")
        XCTAssertFalse(stubborn.isRunning)
    }

    func testDetailsReaderOnOwnProcess() {
        let d = ProcessDetailsReader.read(pid: getpid())
        XCTAssertEqual(d.pid, getpid())
        XCTAssertNotNil(d.path)
        XCTAssertEqual(d.user, NSUserName())
        XCTAssertNotNil(d.startDate)
        XCTAssertGreaterThan(d.threads ?? 0, 0)
        XCTAssertNotNil(d.parentPID)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return condition()
    }
}
