import XCTest
@testable import Adalmon

final class AgentStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func ev(_ name: AgentEvent.Name, session: String = "s1", at: TimeInterval = 0, agentID: String? = nil, agentType: String? = nil,
                    tool: String? = nil, model: String? = nil, notification: String? = nil, to: String? = nil,
                    resolvedModel: String? = nil, resolvedAgent: String? = nil) -> (AgentEvent, Date) {
        (AgentEvent(event: name.rawValue, sessionID: session, agentID: agentID, agentType: agentType, toolName: tool, model: model,
                    toModel: to, notificationType: notification, project: "Adalmon", resolvedModel: resolvedModel,
                    resolvedAgentID: resolvedAgent), t0.addingTimeInterval(at))
    }

    private func run(_ events: [(AgentEvent, Date)]) -> AgentState {
        var state = AgentState()
        for (e, d) in events { state.apply(e, now: d) }
        return state
    }

    func testSessionLifecycle() {
        var state = AgentState()
        func step(_ e: (AgentEvent, Date)) -> AgentStatus? { state.apply(e.0, now: e.1); return state.sessions["s1"]?.status }
        XCTAssertEqual(step(ev(.sessionStart, model: "claude-opus-4-8")), .idle)
        XCTAssertEqual(step(ev(.userPromptSubmit, at: 1)), .thinking)
        XCTAssertEqual(step(ev(.preToolUse, at: 2, tool: "Bash")), .tool("Bash"))
        XCTAssertEqual(step(ev(.postToolUse, at: 3, tool: "Bash")), .thinking)
        XCTAssertEqual(step(ev(.preToolUse, at: 4, tool: "Edit")), .tool("Edit"))
        XCTAssertEqual(step(ev(.postToolUseFailure, at: 5, tool: "Edit")), .thinking)
        XCTAssertEqual(step(ev(.permissionRequest, at: 6)), .waitingPermission)
        XCTAssertEqual(step(ev(.notification, at: 7, notification: "idle_prompt")), .idle)
        XCTAssertEqual(step(ev(.notification, at: 8, notification: "permission_prompt")), .waitingPermission)
        XCTAssertEqual(step(ev(.notification, at: 9, notification: "auth_success")), .waitingPermission, "bilinmeyen bildirim durumu değiştirmez")
        XCTAssertEqual(step(ev(.stop, at: 10)), .done)
        XCTAssertEqual(step(ev(.userPromptSubmit, at: 11)), .thinking)
        XCTAssertEqual(step(ev(.sessionEnd, at: 12)), .ended)
        XCTAssertEqual(step(ev(.preToolUse, at: 13, tool: "Bash")), .ended, "kapanan oturum geç gelen olayla canlanmaz")
        XCTAssertEqual(state.sessions["s1"]?.project, "Adalmon")
        XCTAssertEqual(state.sessions["s1"]?.badge, .opus)
    }

    func testSubagentMatchingByAgentID() {
        let state = run([
            ev(.sessionStart, model: "claude-opus-4-8"),
            ev(.userPromptSubmit, at: 1),
            ev(.preToolUse, at: 2, tool: "Agent"),
            ev(.subagentStart, at: 3, agentID: "a1", agentType: "Explore"),
            ev(.subagentStart, at: 3, agentID: "a2", agentType: "general-purpose"),
            ev(.preToolUse, at: 4, agentID: "a1", tool: "Grep"),      // alt ajanın aracı: alt ajana yazılır
            ev(.permissionRequest, at: 5, agentID: "a2"),
        ])
        let s = state.sessions["s1"]!
        XCTAssertEqual(s.status, .tool("Agent"), "üst oturumun durumu alt ajan olaylarıyla ezilmez")
        XCTAssertEqual(s.subagents.map(\.agentID), ["a1", "a2"])
        XCTAssertEqual(s.subagents[0].status, .tool("Grep"))
        XCTAssertEqual(s.subagents[1].status, .waitingPermission)
        XCTAssertEqual(state.workingAgentCount, 3)
    }

    func testSubagentStopAndResolvedModel() {
        var state = run([
            ev(.sessionStart), ev(.userPromptSubmit, at: 1),
            ev(.subagentStart, at: 2, agentID: "a1", agentType: "Explore"),
            ev(.subagentStop, at: 3, agentID: "a1", agentType: "Explore"),
            ev(.postToolUse, at: 4, tool: "Agent", resolvedModel: "claude-haiku-4-5", resolvedAgent: "a1"),
        ])
        var sub = state.sessions["s1"]!.subagents[0]
        XCTAssertEqual(sub.status, .done)
        XCTAssertEqual(AgentModelBadge(modelID: sub.model), .haiku)
        XCTAssertEqual(state.sessions["s1"]?.status, .thinking)
        // Sonraki istem bitmiş alt ajanları temizler.
        state.apply(ev(.userPromptSubmit, at: 10).0, now: t0.addingTimeInterval(10))
        XCTAssertTrue(state.sessions["s1"]!.subagents.isEmpty)
        sub = AgentSubagent(agentID: "x", agentType: "t", model: nil, status: .done)
        XCTAssertEqual(AgentModelBadge(modelID: sub.model), .unknown)
    }

    func testResolvedModelArrivingBeforeSubagentStart() {
        let state = run([
            ev(.sessionStart),
            ev(.postToolUse, at: 1, tool: "Agent", resolvedModel: "claude-sonnet-4-6", resolvedAgent: "a9"),
            ev(.subagentStart, at: 2, agentID: "a9", agentType: "Plan"),
        ])
        XCTAssertEqual(state.sessions["s1"]!.subagents[0].model, "claude-sonnet-4-6")
    }

    func testInternalSubagentsWithoutTypeAreIgnored() {
        let state = run([
            ev(.sessionStart),
            ev(.subagentStart, at: 1, agentID: "internal"),                        // agent_type yok
            ev(.subagentStart, at: 1, agentType: "Explore"),                       // agent_id yok
            ev(.subagentStop, at: 2, agentID: "ghost", agentType: "Explore"),     // hiç başlamamış
        ])
        XCTAssertTrue(state.sessions["s1"]!.subagents.isEmpty)
    }

    /// DOĞRULANMADI varsayımı belgesi: alt ajan olaylarının session_id'si üst oturumla aynı varsayılır. Farklı gelirse
    /// olay ayrı bir oturum olarak görünür (yanlış eşleşme yerine görünür hata); gerçek veriyle doğrulanınca revize edilecek.
    func testSubagentWithDifferentSessionIDWouldBeSeparateSession() {
        let state = run([ev(.sessionStart), ev(.subagentStart, session: "other", at: 1, agentID: "a1", agentType: "Explore")])
        XCTAssertEqual(state.sessions.count, 2)
        XCTAssertTrue(state.sessions["s1"]!.subagents.isEmpty)
    }

    func testMidSessionStartAndUnknownEnd() {
        var state = AgentState()
        XCTAssertFalse(state.apply(ev(.sessionEnd, session: "ghost").0, now: t0))
        XCTAssertTrue(state.isEmpty)
        XCTAssertTrue(state.apply(ev(.preToolUse, session: "late", tool: "Bash").0, now: t0))
        XCTAssertEqual(state.sessions["late"]?.status, .tool("Bash"))
        XCTAssertEqual(AgentModelBadge(modelID: state.sessions["late"]?.model), .unknown)
        XCTAssertFalse(state.apply(AgentEvent(event: "SomethingNew", sessionID: "late"), now: t0))
    }

    func testPostModelSwitch() {
        let state = run([ev(.sessionStart, model: "claude-opus-4-8"), ev(.postModelSwitch, at: 1, to: "claude-sonnet-4-6")])
        XCTAssertEqual(state.sessions["s1"]?.badge, .sonnet)
    }

    func testStalePruneAndEndedLinger() {
        var state = run([ev(.sessionStart, session: "a"), ev(.sessionStart, session: "b", at: 100), ev(.sessionEnd, session: "b", at: 110)])
        XCTAssertEqual(state.nextPruneDate(), t0.addingTimeInterval(110 + AgentState.endedLinger))
        XCTAssertTrue(state.prune(now: t0.addingTimeInterval(120)).isEmpty)
        XCTAssertEqual(state.prune(now: t0.addingTimeInterval(171)), ["b"], "kapanan oturum 60 sn sonra düşer")
        XCTAssertTrue(state.prune(now: t0.addingTimeInterval(AgentState.staleAfter - 1)).isEmpty)
        XCTAssertEqual(state.prune(now: t0.addingTimeInterval(AgentState.staleAfter)), ["a"], "30 dk olaysız oturum bayat sayılıp düşer")
        XCTAssertTrue(state.isEmpty)
        XCTAssertNil(state.nextPruneDate())
    }

    func testWorkingCountIgnoresIdleDoneEnded() {
        let state = run([
            ev(.sessionStart, session: "a"), ev(.userPromptSubmit, session: "a", at: 1),
            ev(.sessionStart, session: "b"), ev(.stop, session: "b", at: 1),
            ev(.sessionStart, session: "c"), ev(.sessionEnd, session: "c", at: 1),
        ])
        XCTAssertEqual(state.workingAgentCount, 1)
        XCTAssertEqual(state.orderedSessions.count, 3)
    }

    func testModelBadgeMapping() {
        XCTAssertEqual(AgentModelBadge(modelID: "claude-opus-4-8"), .opus)
        XCTAssertEqual(AgentModelBadge(modelID: "claude-opus-4-8[1m]"), .opus)
        XCTAssertEqual(AgentModelBadge(modelID: "claude-sonnet-4-6"), .sonnet)
        XCTAssertEqual(AgentModelBadge(modelID: "claude-haiku-4-5-20251001"), .haiku)
        XCTAssertEqual(AgentModelBadge(modelID: "claude-fable-1"), .fable)
        XCTAssertEqual(AgentModelBadge(modelID: "gpt-5"), .unknown)
        XCTAssertEqual(AgentModelBadge(modelID: nil), .unknown)
        XCTAssertEqual(AgentModelBadge.unknown.label, "bilinmiyor")
    }

    func testEventJSONKeepsOnlyAllowedKeysAndRequiresIDs() throws {
        let json = #"{"event":"PreToolUse","session_id":"s","tool_name":"Bash","prompt":"SECRET","tool_input":{"command":"rm"},"ts":12.5}"#
        let event = try XCTUnwrap(AgentEvent(json: Data(json.utf8)))
        XCTAssertEqual(event.toolName, "Bash")
        XCTAssertEqual(event.timestamp, Date(timeIntervalSince1970: 12.5))
        XCTAssertNil(AgentEvent(json: Data(#"{"event":"Stop"}"#.utf8)))
        XCTAssertNil(AgentEvent(json: Data("[1,2]".utf8)))
        XCTAssertNil(AgentEvent(json: Data("not json".utf8)))
        let long = String(repeating: "x", count: 1000)
        let clipped = try XCTUnwrap(AgentEvent(json: Data(#"{"event":"Stop","session_id":"\#(long)"}"#.utf8)))
        XCTAssertEqual(clipped.sessionID.count, AgentEvent.maxValueLength)
    }

    @MainActor
    func testMonitorSummaryChangesOnlyWhenCountsChange() {
        let monitor = AgentMonitorModel()
        monitor.ingest(ev(.sessionStart).0, now: t0)
        XCTAssertEqual(monitor.summary, AgentSummary(working: 0, sessions: 1))
        monitor.ingest(ev(.userPromptSubmit, at: 1).0, now: t0)
        XCTAssertEqual(monitor.summary, AgentSummary(working: 1, sessions: 1))
        XCTAssertEqual(monitor.lastEventAt, t0)
        monitor.reset()
        XCTAssertEqual(monitor.summary, AgentSummary())
        XCTAssertNil(monitor.lastEventAt)
    }
}
