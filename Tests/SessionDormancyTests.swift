import XCTest
@testable import Adalmon

final class SessionDormancyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    private let limit = SessionDormancy.idleAfter

    private func session(_ id: String = "s1", status: AgentStatus = .idle, lastEvent: TimeInterval = 0, subagents: [AgentSubagent] = [],
                         shells: SessionShells = .empty) -> AgentSession {
        var s = AgentSession(id: id, project: "Adalmon", model: "claude-opus-4-8", status: status, startedAt: t0,
                             lastEventAt: t0.addingTimeInterval(lastEvent))
        s.subagents = subagents
        s.shells = shells
        return s
    }

    func testIdleThresholdIsThirtyMinutes() {
        XCTAssertEqual(SessionDormancy.idleAfter, 1800)
    }

    func testIdleAndDoneSessionsMinimizeOnlyAfterThreshold() {
        for status in [AgentStatus.idle, .done] {
            let s = session(status: status)
            XCTAssertFalse(SessionDormancy.isMinimized(s, override: nil, now: t0.addingTimeInterval(limit - 1)), "\(status)")
            XCTAssertTrue(SessionDormancy.isMinimized(s, override: nil, now: t0.addingTimeInterval(limit)), "\(status)")
            XCTAssertTrue(SessionDormancy.isMinimized(s, override: nil, now: t0.addingTimeInterval(4 * 86_400)), "3-4 gün boşta kalan")
        }
    }

    func testBusySessionsNeverMinimize() {
        let late = t0.addingTimeInterval(10 * 86_400)
        for status in [AgentStatus.thinking, .tool("Bash"), .waitingPermission] {
            XCTAssertFalse(SessionDormancy.isMinimized(session(status: status), override: nil, now: late), "\(status)")
            XCTAssertFalse(SessionDormancy.isMinimized(session(status: status), override: .minimized, now: late), "elle küçültülmüş olsa da çalışırken açılır")
        }
        let working = AgentSubagent(agentID: "a", agentType: "Explore", model: nil, status: .thinking)
        XCTAssertFalse(SessionDormancy.isMinimized(session(subagents: [working]), override: nil, now: late), "çalışan alt ajanı olan oturum")
        let finished = AgentSubagent(agentID: "b", agentType: "Explore", model: nil, status: .done)
        XCTAssertTrue(SessionDormancy.isMinimized(session(subagents: [finished]), override: nil, now: late), "biten alt ajan oturumu tutmaz")
    }

    func testRunningBackgroundShellKeepsSessionOpen() {
        let item = SessionShell(pid: 42, name: "node", ageSeconds: 100, cpuPercent: 1, rssBytes: 1_000_000, hasChildren: false)
        let s = session(shells: SessionShells(items: [item], total: 1))
        XCTAssertFalse(SessionDormancy.isMinimized(s, override: nil, now: t0.addingTimeInterval(86_400)))
    }

    func testEndedSessionIsNeverMinimized() {
        XCTAssertFalse(SessionDormancy.isMinimized(session(status: .ended), override: .minimized, now: t0.addingTimeInterval(86_400)))
    }

    func testManualMinimizeWorksImmediately() {
        XCTAssertTrue(SessionDormancy.isMinimized(session(), override: .minimized, now: t0))
    }

    func testOpeningRestartsTheIdleCounter() {
        let s = session()
        let openedAt = t0.addingTimeInterval(2 * limit)
        XCTAssertTrue(SessionDormancy.isMinimized(s, override: nil, now: openedAt))
        XCTAssertFalse(SessionDormancy.isMinimized(s, override: .opened(at: openedAt), now: openedAt.addingTimeInterval(limit - 1)))
        XCTAssertTrue(SessionDormancy.isMinimized(s, override: .opened(at: openedAt), now: openedAt.addingTimeInterval(limit)))
    }

    func testNewEventAfterOpeningStillCountsFromTheLatest() {
        let s = session(lastEvent: 5000)
        let due = SessionDormancy.dormantDate(s, override: .opened(at: t0.addingTimeInterval(100)))
        XCTAssertEqual(due, t0.addingTimeInterval(5000 + limit))
    }

    func testPartitionKeepsOrderAndSplits() {
        let a = session("a"), b = session("b", status: .thinking), c = session("c", lastEvent: 4000)
        let now = t0.addingTimeInterval(limit + 10)
        let (open, minimized) = SessionDormancy.partition([a, b, c], overrides: [:], now: now)
        XCTAssertEqual(open.map(\.id), ["b", "c"])
        XCTAssertEqual(minimized.map(\.id), ["a"])
        let forced = SessionDormancy.partition([a, b, c], overrides: ["c": .minimized], now: now)
        XCTAssertEqual(forced.minimized.map(\.id), ["a", "c"])
    }

    func testNextDormantDatePicksEarliestFutureAndSkipsManual() {
        let a = session("a", lastEvent: 100), b = session("b", lastEvent: 500), c = session("c", status: .thinking)
        let now = t0.addingTimeInterval(200)
        XCTAssertEqual(SessionDormancy.nextDormantDate([a, b, c], overrides: [:], now: now), t0.addingTimeInterval(100 + limit))
        XCTAssertEqual(SessionDormancy.nextDormantDate([a, b, c], overrides: ["a": .minimized], now: now), t0.addingTimeInterval(500 + limit))
        XCTAssertNil(SessionDormancy.nextDormantDate([a], overrides: [:], now: t0.addingTimeInterval(limit + 1000)), "zaten küçük: zamanlayıcı gerekmez")
    }

    func testIdleText() {
        XCTAssertEqual(SessionDormancy.idleText(since: t0, now: t0.addingTimeInterval(10)), "1 dk")
        XCTAssertEqual(SessionDormancy.idleText(since: t0, now: t0.addingTimeInterval(45 * 60)), "45 dk")
        XCTAssertEqual(SessionDormancy.idleText(since: t0, now: t0.addingTimeInterval(5 * 3600 + 100)), "5 sa")
        XCTAssertEqual(SessionDormancy.idleText(since: t0, now: t0.addingTimeInterval(3 * 86_400 + 100)), "3 g")
        XCTAssertEqual(SessionDormancy.idleText(since: t0, now: t0.addingTimeInterval(-50)), "1 dk", "saat kayması negatif süre göstermez")
    }

    // MARK: İzleyici

    private func event(_ name: AgentEvent.Name, session: String = "s1") -> AgentEvent {
        AgentEvent(event: name.rawValue, sessionID: session, agentID: nil, agentType: nil, toolName: nil, model: nil, toModel: nil,
                   notificationType: nil, project: "Adalmon", resolvedModel: nil, resolvedAgentID: nil, sessionTitle: nil, pid: nil, target: nil)
    }

    @MainActor
    func testMonitorMinimizeRestoreAndAutoReopenOnWork() {
        let monitor = AgentMonitorModel()
        monitor.ingest(event(.sessionStart))
        XCTAssertEqual(monitor.dock.open.map(\.id), ["s1"])
        monitor.minimize("s1")
        XCTAssertEqual(monitor.dock.minimized.map(\.id), ["s1"])
        XCTAssertTrue(monitor.dock.open.isEmpty)
        monitor.restore("s1")
        XCTAssertEqual(monitor.dock.open.map(\.id), ["s1"])
        monitor.minimize("s1")
        monitor.ingest(event(.userPromptSubmit))
        XCTAssertEqual(monitor.dock.open.map(\.id), ["s1"], "çalışmaya başlayan oturum kendiliğinden açılır")
        XCTAssertNil(monitor.dockOverrides["s1"], "elle küçült kararı çalışınca silinir")
        monitor.ingest(event(.stop))
        XCTAssertEqual(monitor.dock.open.map(\.id), ["s1"], "iş bitince eski karar geri gelmez")
    }

    @MainActor
    func testMonitorIgnoresUnknownSessionAndClearsOnReset() {
        let monitor = AgentMonitorModel()
        monitor.minimize("yok")
        XCTAssertTrue(monitor.dockOverrides.isEmpty)
        monitor.ingest(event(.sessionStart))
        monitor.minimize("s1")
        monitor.reset()
        XCTAssertTrue(monitor.dockOverrides.isEmpty)
        XCTAssertTrue(monitor.dock.minimized.isEmpty)
    }

    @MainActor
    func testWebSnapshotListsMinimizedSessionsWithoutRooms() throws {
        let officeRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources/Office")
        let built = try XCTUnwrap(OfficeWebLayout.build(officeRoot: officeRoot))
        let builder = AgentWebSnapshotBuilder(seats: built.seats)
        let data = builder.snapshot(sessions: [], minimized: [session()], now: t0)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((root["rooms"] as? [Any])?.count, 0)
        let list = try XCTUnwrap(root["minimized"] as? [[String: Any]])
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0]["id"] as? String, "s1")
        XCTAssertEqual(list[0]["label"] as? String, "Adalmon")
        XCTAssertNil(list[0]["seat"])
    }
}
