import XCTest
@testable import Adalmon

/// Sahte süreç tablosu: testler ağaç, argv ve CPU sayaçlarını elle kurar.
final class FakeSessionProcessTable: ProcessTableProviding, @unchecked Sendable {
    var entries: [ProcessTableEntry] = []
    var usages: [Int32: ProcessUsageSample] = [:]
    var argvs: [Int32: [String]] = [:]
    var exeNames: [Int32: String] = [:]
    func listProcesses() -> [ProcessTableEntry] { entries }
    func usage(pid: Int32) -> ProcessUsageSample? { usages[pid] }
    func executableName(pid: Int32) -> String? { exeNames[pid] }
    func argv(pid: Int32) -> [String]? { argvs[pid] }

    func add(_ pid: Int32, parent: Int32, _ name: String, started: Date, zombie: Bool = false, argv: [String]? = nil) {
        entries.removeAll { $0.pid == pid }
        entries.append(ProcessTableEntry(pid: pid, ppid: parent, name: name, isZombie: zombie, startedAt: started))
        if let argv { argvs[pid] = argv }
    }
}

final class SessionProcessSamplerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private let wrapperArgv = ["/bin/zsh", "-c", "-l", "source /Users/x/.claude/shell-snapshots/snapshot-zsh-1.sh && eval 'SECRET=abc xcodebuild build'"]

    private func make() -> (FakeSessionProcessTable, SessionProcessSampler) {
        let t = FakeSessionProcessTable()
        t.add(100, parent: 1, "claude", started: now.addingTimeInterval(-3600))
        return (t, SessionProcessSampler(provider: t))
    }

    func testWrapperIsHiddenAndRealCommandShown() {
        let (t, s) = make()
        t.add(200, parent: 100, "zsh", started: now.addingTimeInterval(-60), argv: wrapperArgv)
        t.add(201, parent: 200, "xcodebuild", started: now.addingTimeInterval(-59))
        t.add(202, parent: 201, "swift-frontend", started: now.addingTimeInterval(-50))
        let r = s.sample(roots: [100], now: now)[100]
        XCTAssertEqual(r?.total, 1)
        XCTAssertEqual(r?.items.map(\.name), ["xcodebuild"])
        XCTAssertEqual(r?.items.first?.hasChildren, true)
    }

    func testMCPServersAndShortHooksAreHidden() {
        let (t, s) = make()
        t.add(300, parent: 100, "node", started: now.addingTimeInterval(-3000))
        t.add(301, parent: 100, "python3", started: now.addingTimeInterval(-3000))
        t.add(302, parent: 100, "bash", started: now.addingTimeInterval(-1), argv: ["bash", "/x/hook.sh"]) // hook betiği (kabuk, sarmalayıcı değil)
        t.add(303, parent: 302, "python3", started: now.addingTimeInterval(-1))
        for i in 0..<95 { t.add(Int32(400 + i), parent: 100, "node", started: now.addingTimeInterval(-3000)) }
        let r = s.sample(roots: [100], now: now)[100]
        XCTAssertEqual(r, SessionShells.empty)
    }

    func testYoungProcessesAndZombiesAreSkipped() {
        let (t, s) = make()
        t.add(200, parent: 100, "zsh", started: now.addingTimeInterval(-60), argv: wrapperArgv)
        t.add(201, parent: 200, "sleep", started: now.addingTimeInterval(-1))
        t.add(202, parent: 200, "ps", started: now.addingTimeInterval(-30), zombie: true)
        t.add(203, parent: 200, "sleep", started: now.addingTimeInterval(-10))
        let r = s.sample(roots: [100], now: now)[100]
        XCTAssertEqual(r?.items.map(\.pid), [203])
    }

    func testNestedShellIsSkippedAndLeafShown() {
        let (t, s) = make()
        t.add(200, parent: 100, "zsh", started: now.addingTimeInterval(-60), argv: wrapperArgv)
        t.add(201, parent: 200, "bash", started: now.addingTimeInterval(-59))
        t.add(202, parent: 201, "sleep", started: now.addingTimeInterval(-58))
        let r = s.sample(roots: [100], now: now)[100]
        XCTAssertEqual(r?.items.map(\.name), ["sleep"])
    }

    func testWrapperExecHandoffShowsProcessItself() {
        let (t, s) = make()
        t.add(200, parent: 100, "zsh", started: now.addingTimeInterval(-60), argv: wrapperArgv)
        XCTAssertEqual(s.sample(roots: [100], now: now)[100]?.total, 0, "alt süreçsiz sarmalayıcı listelenmez")
        t.add(200, parent: 100, "sleep", started: now.addingTimeInterval(-60)) // exec: aynı pid + başlangıç, artık kabuk değil
        XCTAssertEqual(s.sample(roots: [100], now: now.addingTimeInterval(5))[100]?.items.map(\.name), ["sleep"])
        XCTAssertEqual(s.sample(roots: [100], now: now.addingTimeInterval(10))[100]?.items.map(\.name), ["sleep"], "hatırlama sürer")
        // Başka pid'li, hiç sarmalayıcı görülmemiş node gizli kalır.
        t.add(300, parent: 100, "node", started: now.addingTimeInterval(-60))
        XCTAssertEqual(s.sample(roots: [100], now: now.addingTimeInterval(15))[100]?.total, 1)
    }

    func testWrapperDetectionRules() {
        XCTAssertTrue(SessionProcessSampler.looksLikeWrapper(argv: wrapperArgv))
        XCTAssertTrue(SessionProcessSampler.looksLikeWrapper(argv: ["zsh", "-lc", "cd /x && claude-helper"]))
        XCTAssertFalse(SessionProcessSampler.looksLikeWrapper(argv: ["zsh", "-c", "echo hi"]), "işaret yok")
        XCTAssertFalse(SessionProcessSampler.looksLikeWrapper(argv: ["zsh", "/path/shell-snapshots/x.sh"]), "-c yok")
        XCTAssertFalse(SessionProcessSampler.looksLikeWrapper(argv: []))
    }

    func testOrderingCapAndTotal() {
        let (t, s) = make()
        t.add(200, parent: 100, "zsh", started: now.addingTimeInterval(-600), argv: wrapperArgv)
        for i in 0..<15 {
            t.add(Int32(210 + i), parent: 200, "job\(i)", started: now.addingTimeInterval(-Double(100 + i * 10)))
        }
        let r = s.sample(roots: [100], now: now)[100]
        XCTAssertEqual(r?.total, 15)
        XCTAssertEqual(r?.items.count, 12)
        XCTAssertEqual(r?.hidden, 3)
        XCTAssertEqual(r?.items.first?.pid, 224, "CPU eşitse en eski (en yüksek yaş) önce")
        // CPU yüksek olan öne çıkar.
        t.usages[215] = ProcessUsageSample(cpuNanoseconds: 0, rssBytes: 0)
        _ = s.sample(roots: [100], now: now)
        t.usages[215] = ProcessUsageSample(cpuNanoseconds: 2_500_000_000, rssBytes: 0)
        let r2 = s.sample(roots: [100], now: now.addingTimeInterval(5))[100]
        XCTAssertEqual(r2?.items.first?.pid, 215)
    }

    func testCPUIsDeltaOverWallTime() {
        let (t, s) = make()
        t.add(200, parent: 100, "zsh", started: now.addingTimeInterval(-600), argv: wrapperArgv)
        t.add(201, parent: 200, "node", started: now.addingTimeInterval(-500))
        t.usages[201] = ProcessUsageSample(cpuNanoseconds: 10_000_000_000, rssBytes: 150 * 1_048_576 + 12_345)
        XCTAssertEqual(s.sample(roots: [100], now: now)[100]?.items.first?.cpuPercent, 0, "ilk örnek: fark yok")
        t.usages[201] = ProcessUsageSample(cpuNanoseconds: 12_500_000_000, rssBytes: 150 * 1_048_576 + 12_345)
        let r = s.sample(roots: [100], now: now.addingTimeInterval(5))[100]?.items.first
        XCTAssertEqual(r?.cpuPercent, 50)
        XCTAssertEqual(r?.rssBytes, 150 * 1_048_576, "MB'a yuvarlanır")
    }

    func testArgvNeverLeaksIntoOutput() {
        let (t, s) = make()
        t.add(200, parent: 100, "zsh", started: now.addingTimeInterval(-60), argv: wrapperArgv)
        t.add(201, parent: 200, "xcodebuild", started: now.addingTimeInterval(-59), argv: ["xcodebuild", "SECRET=abc", "--token=hunter2"])
        t.exeNames[201] = "xcodebuild"
        let r = s.sample(roots: [100], now: now)[100]
        let dump = String(describing: r)
        XCTAssertFalse(dump.contains("SECRET"))
        XCTAssertFalse(dump.contains("abc"))
        XCTAssertFalse(dump.contains("hunter2"))
        XCTAssertFalse(dump.contains("eval"))
        XCTAssertFalse(dump.contains("shell-snapshots"))
    }

    func testNameSanitizing() {
        XCTAssertEqual(SessionProcessSampler.sanitizedName("/usr/bin/xcodebuild"), "xcodebuild")
        XCTAssertEqual(SessionProcessSampler.sanitizedName("a\nb\u{1B}[31mc\u{7F}"), "ab[31mc")
        XCTAssertEqual(SessionProcessSampler.sanitizedName(String(repeating: "x", count: 60)).count, 24)
        XCTAssertEqual(SessionProcessSampler.sanitizedName("\n\t"), "?")
    }

    func testSeveralSessionsShareOneTableRead() {
        let (t, s) = make()
        t.add(150, parent: 1, "claude", started: now.addingTimeInterval(-3600))
        t.add(200, parent: 100, "zsh", started: now.addingTimeInterval(-60), argv: wrapperArgv)
        t.add(201, parent: 200, "sleep", started: now.addingTimeInterval(-59))
        let r = s.sample(roots: [100, 150, 999], now: now)
        XCTAssertEqual(r[100]?.total, 1)
        XCTAssertEqual(r[150], SessionShells.empty)
        XCTAssertEqual(r[999], SessionShells.empty, "olmayan pid")
    }

    // MARK: Gerçek libproc

    /// Gerçek `/bin/sh -c "sleep 20"` çocuğu: test süreci sahte "claude" kökü olur, `sh` sarmalayıcı sayılmaz (argv'sinde işaret yok)
    /// ama exec yapmayan `sh` altındaki sleep listelenir mi sorusu yerine, ham süreç ağacının gerçekten okunduğunu doğrular.
    func testRealLibprocSeesRealChild() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        // "claude" işareti: argv'de geçer, böylece sarmalayıcı sayılır. `; :` sh'nin sleep'i exec etmesini engeller.
        p.arguments = ["-c", "sleep 20; : claude-test-marker"]
        try p.run()
        defer { p.terminate() }
        let me = ProcessInfo.processInfo.processIdentifier
        let real = LibprocProcessTable()
        // Ham tablo: çocuk ve torunu görünür.
        var childPID: Int32 = 0
        var sleepSeen = false
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !sleepSeen {
            let table = real.listProcesses()
            if let c = table.first(where: { $0.pid == p.processIdentifier && $0.ppid == me }) {
                childPID = c.pid
                sleepSeen = table.contains { $0.ppid == childPID && $0.name == "sleep" }
            }
            if !sleepSeen { Thread.sleep(forTimeInterval: 0.1) }
        }
        XCTAssertEqual(childPID, p.processIdentifier)
        XCTAssertTrue(sleepSeen, "sh altında sleep görünmeli")
        let argv = try XCTUnwrap(real.argv(pid: childPID))
        XCTAssertTrue(SessionProcessSampler.looksLikeWrapper(argv: argv))
        // Örnekleyici: sleep yeterince yaşlanınca sarmalayıcı gizli, sleep listelenir.
        let sampler = SessionProcessSampler(provider: real)
        var shells: SessionShells?
        let end = Date().addingTimeInterval(6)
        while Date() < end {
            shells = sampler.sample(roots: [me])[me]
            if shells?.items.contains(where: { $0.name == "sleep" }) == true { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        let sleep = try XCTUnwrap(shells?.items.first { $0.name == "sleep" }, "sleep listelenmeli: \(String(describing: shells))")
        XCTAssertFalse(shells?.items.contains { $0.name == "sh" } ?? true, "sarmalayıcı gizli")
        XCTAssertGreaterThanOrEqual(sleep.ageSeconds, 0)
        XCTAssertGreaterThan(sleep.rssBytes, 0)
    }
}

@MainActor
final class AgentShellPollingTests: XCTestCase {
    private func event(_ name: AgentEvent.Name, session: String = "s1", pid: Int32? = 100) -> AgentEvent {
        AgentEvent(event: name.rawValue, sessionID: session, agentID: nil, agentType: nil, toolName: nil, model: nil, toModel: nil,
                   notificationType: nil, project: "Adalmon", resolvedModel: nil, resolvedAgentID: nil, sessionTitle: nil, pid: pid, target: nil)
    }

    private func fixture() -> (FakeSessionProcessTable, AgentMonitorModel) {
        let t = FakeSessionProcessTable()
        let now = Date()
        t.add(100, parent: 1, "claude", started: now.addingTimeInterval(-3600))
        t.add(200, parent: 100, "zsh", started: now.addingTimeInterval(-60),
              argv: ["zsh", "-c", "source /x/shell-snapshots/a.sh && eval 'sleep 99'"])
        t.add(201, parent: 200, "sleep", started: now.addingTimeInterval(-59))
        let m = AgentMonitorModel(probe: AlwaysAlive(), livenessInterval: 3600, shellSampler: SessionProcessSampler(provider: t), shellInterval: 3600)
        return (t, m)
    }

    private struct AlwaysAlive: ProcessLivenessProbing { func probe(pid: Int32) -> ProcessProbeResult { .alive(startedAt: nil) } }

    func testPollingLifecycleFollowsObserversAndSessions() async {
        let (_, m) = fixture()
        XCTAssertFalse(m.isPollingShells)
        m.ingest(event(.sessionStart))
        XCTAssertFalse(m.isPollingShells, "gözlemci yok → görev yok")
        m.addShellObserver()
        XCTAssertTrue(m.isPollingShells, "gözlemci + pid'li oturum → başlar")
        m.removeShellObserver()
        XCTAssertFalse(m.isPollingShells)
        m.removeShellObserver()
        XCTAssertEqual(m.shellObservers, 0, "eksiye düşmez")
        m.addShellObserver()
        m.ingest(event(.sessionEnd))
        XCTAssertFalse(m.isPollingShells, "oturum kapanınca durur")
        m.removeShellObserver()
    }

    func testObserverWithoutPidSessionDoesNotPoll() {
        let (_, m) = fixture()
        m.ingest(event(.sessionStart, pid: nil))
        m.addShellObserver()
        XCTAssertFalse(m.isPollingShells)
        m.removeShellObserver()
    }

    func testSamplingWritesShellsOnlyOnChangeAndClearsOnStop() async {
        let (t, m) = fixture()
        m.ingest(event(.sessionStart))
        var changes = 0
        m.onStateChange = { _ in changes += 1 }
        m.addShellObserver()
        await m.sampleShells()
        XCTAssertEqual(m.state.sessions["s1"]?.shells.items.map(\.name), ["sleep"])
        let afterFirst = changes
        await m.sampleShells()
        XCTAssertEqual(changes, afterFirst, "değişmeyen örnekleme state yazmaz")
        t.entries.removeAll { $0.pid == 201 }
        await m.sampleShells()
        XCTAssertEqual(m.state.sessions["s1"]?.shells.total, 0)
        t.add(201, parent: 200, "sleep", started: Date().addingTimeInterval(-30))
        await m.sampleShells()
        XCTAssertEqual(m.state.sessions["s1"]?.shells.total, 1)
        m.removeShellObserver()
        XCTAssertEqual(m.state.sessions["s1"]?.shells, SessionShells.empty, "gözlemci kalmayınca bayat veri atılır")
    }

    func testSessionEndClearsShells() async {
        let (_, m) = fixture()
        m.ingest(event(.sessionStart))
        m.addShellObserver()
        await m.sampleShells()
        XCTAssertEqual(m.state.sessions["s1"]?.shells.total, 1)
        m.ingest(event(.sessionEnd))
        XCTAssertEqual(m.state.sessions["s1"]?.shells, SessionShells.empty)
        m.removeShellObserver()
    }
}
