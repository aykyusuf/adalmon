import XCTest
@testable import Adalmon

final class AgentStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func ev(_ name: AgentEvent.Name, session: String = "s1", at: TimeInterval = 0, agentID: String? = nil, agentType: String? = nil,
                    tool: String? = nil, model: String? = nil, notification: String? = nil, to: String? = nil,
                    resolvedModel: String? = nil, resolvedAgent: String? = nil, title: String? = nil, pid: Int32? = nil,
                    target: String? = nil) -> (AgentEvent, Date) {
        (AgentEvent(event: name.rawValue, sessionID: session, agentID: agentID, agentType: agentType, toolName: tool, model: model,
                    toModel: to, notificationType: notification, project: "Adalmon", resolvedModel: resolvedModel,
                    resolvedAgentID: resolvedAgent, sessionTitle: title, pid: pid, target: target), t0.addingTimeInterval(at))
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

    // MARK: Araç etkinliği (konuşma balonu girdisi)

    func testToolEventsSetActivityAndTargetOnTheMainAgent() {
        var state = AgentState()
        state.apply(ev(.sessionStart).0, now: t0)
        state.apply(ev(.userPromptSubmit, at: 1).0, now: t0.addingTimeInterval(1))
        XCTAssertNil(state.sessions["s1"]?.activity)
        XCTAssertEqual(state.sessions["s1"]?.activityAt, t0.addingTimeInterval(1))
        state.apply(ev(.preToolUse, at: 2, tool: "Edit", target: "main.swift").0, now: t0.addingTimeInterval(2))
        var s = state.sessions["s1"]
        XCTAssertEqual(s?.status, .tool("Edit"))
        XCTAssertEqual(s?.activity, "Edit")
        XCTAssertEqual(s?.target, "main.swift")
        XCTAssertEqual(s?.activityAt, t0.addingTimeInterval(2))
        state.apply(ev(.preToolUse, at: 3, tool: "Grep").0, now: t0.addingTimeInterval(3))
        s = state.sessions["s1"]
        XCTAssertEqual(s?.activity, "Grep")
        XCTAssertNil(s?.target, "hedefsiz araç önceki hedefi taşımaz")
        state.apply(ev(.preToolUse, at: 4, tool: "Bash", target: "swift").0, now: t0.addingTimeInterval(4))
        XCTAssertEqual(state.sessions["s1"]?.target, "swift")
        state.apply(ev(.postToolUse, at: 5, tool: "Bash").0, now: t0.addingTimeInterval(5))
        s = state.sessions["s1"]
        XCTAssertEqual(s?.status, .thinking)
        XCTAssertNil(s?.activity); XCTAssertNil(s?.target)
        state.apply(ev(.preToolUse, at: 6, tool: "Read", target: "a.txt").0, now: t0.addingTimeInterval(6))
        state.apply(ev(.stop, at: 7).0, now: t0.addingTimeInterval(7))
        XCTAssertEqual(state.sessions["s1"]?.status, .done)
        XCTAssertNil(state.sessions["s1"]?.activity); XCTAssertNil(state.sessions["s1"]?.target)
    }

    func testSubagentToolEventsGoToTheMatchingSubagentOnly() {
        var state = run([ev(.sessionStart), ev(.userPromptSubmit, at: 1), ev(.subagentStart, at: 2, agentID: "a1", agentType: "Explore"),
                         ev(.subagentStart, at: 2, agentID: "a2", agentType: "Plan")])
        state.apply(ev(.preToolUse, at: 3, agentID: "a1", tool: "Edit", target: "x.swift").0, now: t0.addingTimeInterval(3))
        let s = state.sessions["s1"]
        XCTAssertEqual(s?.subagents.first { $0.agentID == "a1" }?.activity, "Edit")
        XCTAssertEqual(s?.subagents.first { $0.agentID == "a1" }?.target, "x.swift")
        XCTAssertEqual(s?.subagents.first { $0.agentID == "a1" }?.activityAt, t0.addingTimeInterval(3))
        XCTAssertNil(s?.subagents.first { $0.agentID == "a2" }?.activity)
        XCTAssertEqual(s?.subagents.first { $0.agentID == "a2" }?.activityAt, t0.addingTimeInterval(2), "başka alt ajanın zamanı değişmez")
        XCTAssertNil(s?.activity, "ana ajana yazılmaz")
        XCTAssertEqual(s?.status, .thinking)
        // Alt ajanın araç sonucu yalnızca onu temizler; alt ajan bitince etkinlik silinir.
        state.apply(ev(.postToolUse, at: 4, agentID: "a1", tool: "Edit").0, now: t0.addingTimeInterval(4))
        XCTAssertNil(state.sessions["s1"]?.subagents.first { $0.agentID == "a1" }?.activity)
        state.apply(ev(.preToolUse, at: 5, agentID: "a1", tool: "Bash", target: "ls").0, now: t0.addingTimeInterval(5))
        state.apply(ev(.subagentStop, at: 6, agentID: "a1", agentType: "Explore").0, now: t0.addingTimeInterval(6))
        let a1 = state.sessions["s1"]?.subagents.first { $0.agentID == "a1" }
        XCTAssertEqual(a1?.status, .done)
        XCTAssertNil(a1?.activity); XCTAssertNil(a1?.target)
        // Bilinmeyen agent_id (listelenmeyen iç ajan) mevcut davranışla ana ajana yazılır.
        state.apply(ev(.preToolUse, at: 7, agentID: "ghost", tool: "Read").0, now: t0.addingTimeInterval(7))
        XCTAssertEqual(state.sessions["s1"]?.activity, "Read")
    }

    func testEventTargetIsSanitizedAndOptional() throws {
        let json = #"{"event":"PreToolUse","session_id":"s","tool_name":"Edit","target":"  ma\u0001in.swift  ","tool_input":{"command":"SECRET"}}"#
        let e = try XCTUnwrap(AgentEvent(json: Data(json.utf8)))
        XCTAssertEqual(e.target, "main.swift", "kontrol karakteri atılır, uçlar kırpılır")
        let long = try XCTUnwrap(AgentEvent(json: Data(#"{"event":"PreToolUse","session_id":"s","target":"\#(String(repeating: "a", count: 90))"}"#.utf8)))
        XCTAssertEqual(long.target?.count, 40)
        XCTAssertNil(try XCTUnwrap(AgentEvent(json: Data(#"{"event":"PreToolUse","session_id":"s","target":"\u0001  "}"#.utf8))).target)
        XCTAssertNil(try XCTUnwrap(AgentEvent(json: Data(#"{"event":"PreToolUse","session_id":"s"}"#.utf8))).target)
        XCTAssertTrue(AgentEvent.allowedKeys.contains("target"))
        var state = AgentState()
        state.clearTargets()
        state.apply(ev(.preToolUse, tool: "Edit", target: "a.swift").0, now: t0)
        state.clearTargets()
        XCTAssertNil(state.sessions["s1"]?.target)
        XCTAssertEqual(state.sessions["s1"]?.activity, "Edit", "yalnızca hedef silinir")
    }

    func testSessionTitleUpdatesDisplayName() {
        var state = AgentState()
        state.apply(ev(.sessionStart).0, now: t0)
        XCTAssertNil(state.sessions["s1"]?.title)
        XCTAssertEqual(state.sessions["s1"]?.displayName, "Adalmon", "başlık yoksa proje adı")
        XCTAssertNil(state.sessions["s1"]?.secondaryName)

        state.apply(ev(.userPromptSubmit, at: 1, title: "Ajan paneli").0, now: t0.addingTimeInterval(1))
        XCTAssertEqual(state.sessions["s1"]?.displayName, "Ajan paneli")
        XCTAssertEqual(state.sessions["s1"]?.secondaryName, "Adalmon")

        state.apply(ev(.preToolUse, at: 2, tool: "Bash").0, now: t0.addingTimeInterval(2))
        XCTAssertEqual(state.sessions["s1"]?.displayName, "Ajan paneli", "başlıksız olay mevcut adı korur")
        state.apply(ev(.userPromptSubmit, at: 3, title: "   ").0, now: t0.addingTimeInterval(3))
        XCTAssertEqual(state.sessions["s1"]?.displayName, "Ajan paneli", "boş başlık mevcut adı silmez")
        state.apply(ev(.userPromptSubmit, at: 4, title: "Yeni ad").0, now: t0.addingTimeInterval(4))
        XCTAssertEqual(state.sessions["s1"]?.displayName, "Yeni ad", "/rename sonrası ad güncellenir")

        // Oturum ortasında açılan Adalmon: ilk olaydaki başlık oturumu oluştururken uygulanır.
        state.apply(ev(.notification, session: "s2", title: "Ortadan").0, now: t0)
        XCTAssertEqual(state.sessions["s2"]?.displayName, "Ortadan")
    }

    func testEventSanitizesTitleAndIgnoresContentKeys() throws {
        let long = String(repeating: "ş", count: 500)
        let body = #"{"event":"SessionStart","session_id":"s","session_title":"a\u0001b\nc  d","prompt":"SECRET"}"#
        let event = try XCTUnwrap(AgentEvent(json: Data(body.utf8)))
        XCTAssertEqual(event.sessionTitle, "a b c d")
        XCTAssertEqual(AgentEvent(event: "Stop", sessionID: "s", sessionTitle: long).sessionTitle?.count, AgentEvent.maxValueLength)
        XCTAssertNil(AgentEvent(event: "Stop", sessionID: "s", sessionTitle: " \n ").sessionTitle)
        XCTAssertTrue(AgentEvent.allowedKeys.contains("session_title"))
        XCTAssertFalse(AgentEvent.allowedKeys.contains("prompt"))
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
        // "a" çalışıyor (30 dk), "b" kapandı (60 sn).
        var state = run([ev(.sessionStart, session: "a"), ev(.userPromptSubmit, session: "a", at: 1),
                         ev(.sessionStart, session: "b", at: 100), ev(.sessionEnd, session: "b", at: 110)])
        XCTAssertEqual(state.nextPruneDate(), t0.addingTimeInterval(110 + AgentState.endedLinger))
        XCTAssertTrue(state.prune(now: t0.addingTimeInterval(120)).isEmpty)
        XCTAssertEqual(state.prune(now: t0.addingTimeInterval(171)), ["b"], "kapanan oturum 60 sn sonra düşer")
        XCTAssertTrue(state.prune(now: t0.addingTimeInterval(1 + AgentState.staleAfter - 1)).isEmpty)
        XCTAssertEqual(state.prune(now: t0.addingTimeInterval(1 + AgentState.staleAfter)), ["a"], "30 dk olaysız çalışan oturum düşer")
        XCTAssertTrue(state.isEmpty)
        XCTAssertNil(state.nextPruneDate())
    }

    func testRestingSessionsWithoutPIDGoStaleAfterTenMinutes() {
        var state = run([ev(.sessionStart, session: "idle"), ev(.sessionStart, session: "done"), ev(.stop, session: "done", at: 1),
                         ev(.sessionStart, session: "wait"), ev(.permissionRequest, session: "wait", at: 1),
                         ev(.sessionStart, session: "tool"), ev(.preToolUse, session: "tool", at: 1, tool: "Bash")])
        XCTAssertEqual(state.nextPruneDate(), t0.addingTimeInterval(AgentState.restingStaleAfter))
        XCTAssertTrue(state.prune(now: t0.addingTimeInterval(AgentState.restingStaleAfter - 1)).isEmpty)
        XCTAssertEqual(Set(state.prune(now: t0.addingTimeInterval(AgentState.restingStaleAfter + 1))), ["idle", "done"],
                       "bitti/boşta 10 dk; izin bekleyen ve çalışan 30 dk")
        XCTAssertEqual(Set(state.prune(now: t0.addingTimeInterval(AgentState.staleAfter + 1))), ["wait", "tool"])
    }

    func testSessionWithKnownPIDNeverGoesStale() {
        var state = run([ev(.sessionStart, pid: 4242), ev(.stop, at: 1, pid: 4242)])
        XCTAssertEqual(state.sessions["s1"]?.pid, 4242)
        XCTAssertTrue(state.prune(now: t0.addingTimeInterval(24 * 3600)).isEmpty, "pid'li canlı oturum olaysız da düşmez")
        XCTAssertNil(state.nextPruneDate(), "zamanlayıcı gerekmez; canlılık yoklaması kapatır")
        state.apply(ev(.sessionEnd, at: 5, pid: 4242).0, now: t0.addingTimeInterval(5))
        XCTAssertEqual(state.prune(now: t0.addingTimeInterval(66)), ["s1"], "SessionEnd yine 60 sn sonra düşürür")
    }

    // MARK: pid ve süreç canlılığı

    func testPIDFieldIsRecordedAndLastKnownKept() {
        var state = run([ev(.sessionStart), ev(.userPromptSubmit, at: 1, pid: 111)])
        XCTAssertEqual(state.sessions["s1"]?.pid, 111, "SessionStart pid'siz (eski betik/ara kabuk), sonraki olay verir")
        state.apply(ev(.preToolUse, at: 2, tool: "Bash").0, now: t0.addingTimeInterval(2))
        XCTAssertEqual(state.sessions["s1"]?.pid, 111, "pid'siz olay son bilineni silmez")
        let probe = FakeProcessTable()
        probe.set(111, .alive(startedAt: t0))
        state.applyLiveness(using: probe, now: t0.addingTimeInterval(2))
        XCTAssertEqual(state.sessions["s1"]?.pidStartedAt, t0)
        state.apply(ev(.preToolUse, at: 3, tool: "Bash", pid: 111).0, now: t0.addingTimeInterval(3))
        XCTAssertEqual(state.sessions["s1"]?.pidStartedAt, t0, "aynı pid kaydedilen başlangıcı sıfırlamaz")
        state.apply(ev(.preToolUse, at: 4, tool: "Bash", pid: 222).0, now: t0.addingTimeInterval(4))
        XCTAssertEqual(state.sessions["s1"]?.pid, 222)
        XCTAssertNil(state.sessions["s1"]?.pidStartedAt, "pid değişince başlangıç yeniden kaydedilir")
        XCTAssertEqual(run([ev(.preToolUse, session: "mid", tool: "Bash", pid: 9)]).sessions["mid"]?.pid, 9, "oturum ortasında açılan oturum da pid alır")
    }

    func testEventPIDParsingIsStrict() throws {
        func pid(_ raw: String) throws -> Int32? {
            try XCTUnwrap(AgentEvent(json: Data(#"{"event":"Stop","session_id":"s","pid":\#(raw)}"#.utf8))).pid
        }
        XCTAssertEqual(try pid("12345"), 12345)
        for bad in ["\"12345\"", "1", "0", "-7", "12.5", "true", "99999999999", "null", "[1]"] { XCTAssertNil(try pid(bad), bad) }
        XCTAssertNil(AgentEvent(event: "Stop", sessionID: "s", pid: 1).pid)
        XCTAssertEqual(AgentEvent(event: "Stop", sessionID: "s", pid: 2).pid, 2)
    }

    func testDeadProcessClosesSessionAndSubagents() {
        let probe = FakeProcessTable()
        var state = run([ev(.sessionStart, pid: 100), ev(.userPromptSubmit, at: 1, pid: 100),
                         ev(.subagentStart, at: 2, agentID: "a1", agentType: "Explore"), ev(.sessionStart, session: "other", pid: 200)])
        probe.set(100, .alive(startedAt: t0.addingTimeInterval(-50)))
        probe.set(200, .alive(startedAt: t0.addingTimeInterval(-50)))
        XCTAssertTrue(state.applyLiveness(using: probe, now: t0.addingTimeInterval(10)).isEmpty)
        XCTAssertEqual(state.sessions["s1"]?.status, .thinking)
        probe.set(100, .dead)
        let t = t0.addingTimeInterval(20)
        XCTAssertEqual(state.applyLiveness(using: probe, now: t), ["s1"])
        XCTAssertEqual(state.sessions["s1"]?.status, .ended)
        XCTAssertEqual(state.sessions["s1"]?.subagents.map(\.status), [.ended])
        XCTAssertEqual(state.sessions["other"]?.status, .idle, "diğer oturum etkilenmez")
        XCTAssertEqual(state.workingAgentCount, 0)
        XCTAssertEqual(state.nextPruneDate(), t.addingTimeInterval(AgentState.exitedLinger), "ölü süreç: 10 sn sonra düşer (olaydan bağımsız)")
        XCTAssertTrue(state.prune(now: t.addingTimeInterval(9)).isEmpty)
        XCTAssertEqual(state.prune(now: t.addingTimeInterval(10)), ["s1"])
        XCTAssertTrue(state.applyLiveness(using: probe, now: t).isEmpty, "kapalı oturum bir daha yoklanmaz")
    }

    func testEPERMCountsAsAliveAndUnknownStartDoesNotClose() {
        // Gerçek yoklama EPERM'i `.alive(startedAt: nil)` olarak bildirir; başlangıç zamanı bilinmese de oturum kapanmaz.
        let probe = FakeProcessTable()
        probe.set(100, .alive(startedAt: nil))
        var state = run([ev(.sessionStart, pid: 100)])
        for i in 1...3 { XCTAssertTrue(state.applyLiveness(using: probe, now: t0.addingTimeInterval(Double(i) * 5)).isEmpty) }
        XCTAssertEqual(state.sessions["s1"]?.status, .idle)
        XCTAssertNil(state.sessions["s1"]?.pidStartedAt)
    }

    func testPIDReuseClosesSession() {
        let probe = FakeProcessTable()
        var state = run([ev(.sessionStart, pid: 100)])
        probe.set(100, .alive(startedAt: t0.addingTimeInterval(-300)))
        XCTAssertTrue(state.applyLiveness(using: probe, now: t0.addingTimeInterval(5)).isEmpty)
        XCTAssertEqual(state.sessions["s1"]?.pidStartedAt, t0.addingTimeInterval(-300), "ilk görüşte başlangıç kaydedilir")
        probe.set(100, .alive(startedAt: t0.addingTimeInterval(40))) // aynı pid, başka süreç
        XCTAssertEqual(state.applyLiveness(using: probe, now: t0.addingTimeInterval(50)), ["s1"])
        XCTAssertEqual(state.sessions["s1"]?.status, .ended)
    }

    func testPIDReuseBeforeFirstProbeIsCaughtByEventTime() {
        // Süreç, oturumun son olayından sonra doğduysa kaydedilmiş başlangıç olmasa da başka süreçtir.
        let probe = FakeProcessTable()
        var state = run([ev(.sessionStart, pid: 100), ev(.userPromptSubmit, at: 10, pid: 100)])
        probe.set(100, .alive(startedAt: t0.addingTimeInterval(10 + AgentState.pidReuseSlack + 1)))
        XCTAssertEqual(state.applyLiveness(using: probe, now: t0.addingTimeInterval(30)), ["s1"])
        // Olaydan önce doğan süreç meşrudur.
        var ok = run([ev(.sessionStart, pid: 100)])
        probe.set(100, .alive(startedAt: t0.addingTimeInterval(-1)))
        XCTAssertTrue(ok.applyLiveness(using: probe, now: t0.addingTimeInterval(30)).isEmpty)
    }

    func testSessionsWithoutPIDKeepLegacyBehaviorAndAreNeverProbed() {
        let probe = FakeProcessTable()
        var state = run([ev(.sessionStart), ev(.userPromptSubmit, at: 1)])
        XCTAssertTrue(state.livenessTargets.isEmpty)
        XCTAssertTrue(state.applyLiveness(using: probe, now: t0.addingTimeInterval(5)).isEmpty)
        XCTAssertEqual(probe.callCount, 0)
        XCTAssertEqual(state.prune(now: t0.addingTimeInterval(1 + AgentState.staleAfter)), ["s1"], "eski 30 dk bayatlama sürer")
    }

    func testSystemProbeSeesLiveAndDeadProcesses() throws {
        let probe = SystemProcessProbe()
        let me = ProcessInfo.processInfo.processIdentifier
        guard case .alive(let started) = probe.probe(pid: me) else { return XCTFail("kendi süreç yaşıyor olmalı") }
        let startedAt = try XCTUnwrap(started, "sysctl ile başlangıç zamanı okunmalı")
        XCTAssertLessThan(startedAt, Date.now)
        XCTAssertGreaterThan(startedAt, Date.now.addingTimeInterval(-30 * 24 * 3600))
        XCTAssertEqual(probe.probe(pid: 1), .dead, "pid <= 1 geçersiz")
        // Bitmiş ve toplanmış bir alt sürecin pid'i ölü görünmeli.
        let child = Process()
        child.executableURL = URL(filePath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        XCTAssertEqual(probe.probe(pid: child.processIdentifier), .dead)
        // Başka kullanıcıya (root) ait süreç: kill EPERM verir ama yoklama yaşıyor demelidir.
        if let rootPID = Self.rootOwnedPID() {
            XCTAssertEqual(kill(rootPID, 0), -1)
            XCTAssertEqual(errno, EPERM)
            XCTAssertNotEqual(probe.probe(pid: rootPID), .dead, "EPERM = yaşıyor")
        }
    }

    /// Root'a ait, pid > 1 bir süreç (EPERM yolu için); bulunamazsa nil.
    private static func rootOwnedPID() -> Int32? {
        let ps = Process()
        ps.executableURL = URL(filePath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,user="]
        let out = Pipe()
        ps.standardOutput = out
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return nil }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ")
            if parts.count == 2, parts[1] == "root", let pid = Int32(parts[0]), pid > 1 { return pid }
        }
        return nil
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

    @MainActor
    func testLivenessPollingStartsOnlyWithActivePIDSessionsAndStops() {
        let probe = FakeProcessTable()
        let monitor = AgentMonitorModel(probe: probe, livenessInterval: 3600)
        XCTAssertFalse(monitor.isPollingLiveness, "oturum yokken zamanlayıcı yok")
        monitor.ingest(ev(.sessionStart).0, now: t0)
        XCTAssertFalse(monitor.isPollingLiveness, "pid'siz oturum için yoklama yok")
        monitor.ingest(ev(.userPromptSubmit, session: "p", at: 1, pid: 100).0, now: t0)
        XCTAssertTrue(monitor.isPollingLiveness)
        probe.set(100, .alive(startedAt: t0.addingTimeInterval(-10)))
        monitor.pollLiveness(now: t0.addingTimeInterval(5))
        XCTAssertTrue(monitor.isPollingLiveness, "canlı: yoklama sürer")
        XCTAssertEqual(monitor.summary, AgentSummary(working: 1, sessions: 2))
        probe.set(100, .dead)
        monitor.pollLiveness(now: t0.addingTimeInterval(10))
        XCTAssertEqual(monitor.state.sessions["p"]?.status, .ended)
        XCTAssertEqual(monitor.summary, AgentSummary(working: 0, sessions: 2))
        XCTAssertFalse(monitor.isPollingLiveness, "kapanmamış pid'li oturum kalmadı: zamanlayıcı durur")
        monitor.prune(now: t0.addingTimeInterval(21))
        XCTAssertNil(monitor.state.sessions["p"], "10 sn sonra düşer")
        monitor.ingest(ev(.stop, session: "q", pid: 300).0, now: t0.addingTimeInterval(30))
        XCTAssertTrue(monitor.isPollingLiveness)
        monitor.reset()
        XCTAssertFalse(monitor.isPollingLiveness, "özellik kapanınca (reset) zamanlayıcı yok")
    }

    @MainActor
    func testLivenessTimerFiresAndClosesDeadSession() async throws {
        let probe = FakeProcessTable()
        probe.set(100, .dead)
        let monitor = AgentMonitorModel(probe: probe, livenessInterval: 0.05)
        monitor.ingest(ev(.userPromptSubmit, pid: 100).0, now: .now)
        XCTAssertTrue(monitor.isPollingLiveness)
        for _ in 0..<60 where monitor.state.sessions["s1"]?.status != .ended { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(monitor.state.sessions["s1"]?.status, .ended)
        XCTAssertFalse(monitor.isPollingLiveness)
        monitor.reset()
    }
}

/// Sahte süreç tablosu: kayıtsız pid = ölü.
private final class FakeProcessTable: ProcessLivenessProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var table: [Int32: ProcessProbeResult] = [:]
    private var calls = 0

    func set(_ pid: Int32, _ result: ProcessProbeResult) { lock.lock(); table[pid] = result; lock.unlock() }
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }

    func probe(pid: Int32) -> ProcessProbeResult {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return table[pid] ?? .dead
    }
}

// MARK: Adalmon oturumdan sonra başladığında / olay kaçırıldığında

extension AgentStateTests {
    private func late(_ name: AgentEvent.Name, at: TimeInterval, agent: String? = nil, type: String? = nil, tool: String? = nil) -> (AgentEvent, Date) {
        ev(name, session: "late", at: at, agentID: agent, agentType: type, tool: tool)
    }

    func testUnknownSubagentIsAdoptedFromItsOwnToolEvent() {
        var state = AgentState()
        // Adalmon oturumdan sonra açıldı: SessionStart ve SubagentStart kaçırıldı; alt ajanın araç olayları geliyor.
        let (e1, d1) = late(.preToolUse, at: 0, agent: "bg1", type: "crew-chief:implementer-hard", tool: "Read")
        state.apply(e1, now: d1)
        let s = state.sessions["late"]
        XCTAssertEqual(s?.subagents.map(\.agentID), ["bg1"], "alt ajan olaydan listeye alınmalı")
        XCTAssertEqual(s?.subagents.first?.agentType, "crew-chief:implementer-hard")
        XCTAssertEqual(s?.subagents.first?.status, .tool("Read"))
        XCTAssertNotEqual(s?.status, .tool("Read"), "alt ajanın aracı ana ajanın durumuna yazılmamalı")
        // İkinci olay yinelemez, durumu günceller.
        let (e2, d2) = late(.postToolUse, at: 1, agent: "bg1", type: "crew-chief:implementer-hard", tool: "Read")
        state.apply(e2, now: d2)
        XCTAssertEqual(state.sessions["late"]?.subagents.count, 1)
        XCTAssertEqual(state.sessions["late"]?.subagents.first?.status, .thinking)
        // Başka bir arka plan ajanı da aynı şekilde.
        let (e3, d3) = late(.permissionRequest, at: 2, agent: "bg2", type: "crew-chief:deep-reader")
        state.apply(e3, now: d3)
        XCTAssertEqual(state.sessions["late"]?.subagents.map(\.agentID), ["bg1", "bg2"])
        XCTAssertEqual(state.sessions["late"]?.subagents.last?.status, .waitingPermission)
    }

    func testFinishedSubagentIsNotResurrectedByALateEvent() {
        var state = AgentState()
        for (e, d) in [late(.sessionStart, at: 0), late(.subagentStart, at: 1, agent: "a", type: "Explore"),
                       late(.subagentStop, at: 2, agent: "a", type: "Explore"), late(.userPromptSubmit, at: 3)] { state.apply(e, now: d) }
        XCTAssertTrue(state.sessions["late"]?.subagents.isEmpty ?? false, "yeni istemde biten ajan temizlenir")
        let (e, d) = late(.postToolUse, at: 4, agent: "a", type: "Explore", tool: "Bash")
        state.apply(e, now: d)
        XCTAssertTrue(state.sessions["late"]?.subagents.isEmpty ?? false, "bitmiş ajan geç gelen olayla geri gelmemeli")
        // Aynı kimlik gerçekten yeniden başlatılırsa canlıdır.
        let (s2, d2) = late(.subagentStart, at: 5, agent: "a", type: "Explore")
        state.apply(s2, now: d2)
        XCTAssertEqual(state.sessions["late"]?.subagents.map(\.agentID), ["a"])
    }

    func testEventsWithoutAgentIDStillDriveTheLead() {
        var state = AgentState()
        let (e, d) = late(.preToolUse, at: 0, tool: "Bash")
        state.apply(e, now: d)
        XCTAssertEqual(state.sessions["late"]?.status, .tool("Bash"))
        XCTAssertTrue(state.sessions["late"]?.subagents.isEmpty ?? false)
    }

    func testSilentSubagentIsPrunedAfterStalenessAndNotReadded() {
        var state = AgentState()
        for (e, d) in [late(.sessionStart, at: 0), late(.subagentStart, at: 1, agent: "z", type: "Explore")] { state.apply(e, now: d) }
        XCTAssertNotNil(state.nextPruneDate(), "alt ajan için bayatlama zamanlayıcısı gerekir")
        let before = t0.addingTimeInterval(AgentState.subagentStaleAfter - 5)
        XCTAssertFalse(state.pruneSubagents(now: before))
        let after = t0.addingTimeInterval(AgentState.subagentStaleAfter + 10)
        XCTAssertTrue(state.pruneSubagents(now: after))
        XCTAssertTrue(state.sessions["late"]?.subagents.isEmpty ?? false)
        let (e, d) = late(.preToolUse, at: AgentState.subagentStaleAfter + 20, agent: "z", type: "Explore", tool: "Bash")
        state.apply(e, now: d)
        XCTAssertTrue(state.sessions["late"]?.subagents.isEmpty ?? false, "bayat diye düşen ajan hemen geri eklenmez")
    }

    func testActiveSubagentIsNotPrunedAndDoneOnesNeverBlockPruneTimer() {
        var state = AgentState()
        for (e, d) in [late(.sessionStart, at: 0), late(.subagentStart, at: 1, agent: "k", type: "Explore"),
                       late(.preToolUse, at: AgentState.subagentStaleAfter - 60, agent: "k", type: "Explore", tool: "Bash")] { state.apply(e, now: d) }
        XCTAssertFalse(state.pruneSubagents(now: t0.addingTimeInterval(AgentState.subagentStaleAfter + 30)), "yeni olay göndermiş ajan bayat sayılmaz")
        let (stop, sd) = late(.subagentStop, at: AgentState.subagentStaleAfter + 31, agent: "k", type: "Explore")
        state.apply(stop, now: sd)
        XCTAssertNil(state.nextPruneDate().flatMap { $0 > t0.addingTimeInterval(AgentState.subagentStaleAfter + 31) ? nil : $0 } ?? nil)
    }
}

// MARK: Süreç taramasıyla "bekleyen oturum" (Adalmon sonradan açıldı / oturum boşta ve olay yok)

extension AgentStateTests {
    func testDiscoveryFilterKeepsOnlyInteractiveClaudeSessions() {
        let found = ClaudeProcessDiscovery.filter([
            .init(pid: 10, argv: ["claude", "--dangerously-skip-permissions"], cwd: "/Users/x/Documents/proje-a"),
            .init(pid: 11, argv: ["/Users/x/.local/bin/claude"], cwd: "/Users/x/proje-b"),
            .init(pid: 12, argv: ["claude", "-p", "merhaba"], cwd: "/tmp/test"),
            .init(pid: 13, argv: ["claude", "--print", "x"], cwd: "/tmp/test"),
            .init(pid: 14, argv: ["claude", "mcp", "serve"], cwd: "/tmp"),
            .init(pid: 15, argv: ["claude", "--chrome-native-host"], cwd: "/tmp"),
            .init(pid: 16, argv: ["node", "claude"], cwd: "/tmp"),
            .init(pid: 17, argv: ["claude"], cwd: ""),
        ])
        XCTAssertEqual(found.map(\.pid), [10, 11, 17])
        XCTAssertEqual(found.first?.project, "proje-a")
        XCTAssertEqual(found.last?.project, "?")
    }

    func testDiscoveredSessionsAppearAsIdleAndSkipKnownPIDs() {
        var state = AgentState()
        // Pid 5 için gerçek oturum zaten var.
        state.apply(ev(.sessionStart, session: "gercek", pid: 5).0, now: t0)
        let changed = state.discoverSessions([.init(pid: 5, project: "a"), .init(pid: 6, project: "b")], now: t0)
        XCTAssertTrue(changed)
        XCTAssertEqual(Set(state.sessions.keys), ["gercek", "discovered-6"])
        let d = state.sessions["discovered-6"]
        XCTAssertEqual(d?.status, .idle)
        XCTAssertEqual(d?.discovered, true)
        XCTAssertEqual(d?.pid, 6)
        XCTAssertEqual(d?.displayName, "b")
        XCTAssertFalse(state.discoverSessions([.init(pid: 6, project: "b")], now: t0), "aynı süreç tekrar eklenmez")
        XCTAssertEqual(state.livenessTargets.map(\.pid).sorted(), [5, 6], "ölünce canlılık yoklaması kapatır")
    }

    func testFirstRealEventReplacesThePlaceholderByPIDOrByProject() {
        var state = AgentState()
        state.discoverSessions([.init(pid: 6, project: "adaltek_social"), .init(pid: 7, project: "diger")], now: t0)
        // pid ile eşleşme
        state.apply(ev(.userPromptSubmit, session: "social-1", pid: 6).0, now: t0.addingTimeInterval(1))
        XCTAssertNil(state.sessions["discovered-6"], "gerçek olay yer tutucunun yerini alır")
        XCTAssertNotNil(state.sessions["social-1"])
        XCTAssertNotNil(state.sessions["discovered-7"], "başka sürecin yer tutucusuna dokunulmaz")
        // Eski betik: pid yok → aynı proje adındaki tek yer tutucu.
        var other = AgentState()
        other.discoverSessions([.init(pid: 8, project: "Adalmon")], now: t0)
        other.apply(ev(.sessionStart, session: "x").0, now: t0.addingTimeInterval(1))    // ev() project = "Adalmon"
        XCTAssertNil(other.sessions["discovered-8"])
        XCTAssertEqual(Set(other.sessions.keys), ["x"])
    }

    func testPlaceholderGoesAwayWhenItsProcessDies() {
        var state = AgentState()
        state.discoverSessions([.init(pid: 99, project: "olu")], now: t0)
        struct Dead: ProcessLivenessProbing { func probe(pid: Int32) -> ProcessProbeResult { .dead } }
        let closed = state.applyLiveness(using: Dead(), now: t0.addingTimeInterval(2))
        XCTAssertEqual(closed, ["discovered-99"])
        state.prune(now: t0.addingTimeInterval(2 + AgentState.exitedLinger + 1))
        XCTAssertTrue(state.sessions.isEmpty)
    }

    @MainActor
    func testMonitorDiscoveryCreatesPlaceholderThenRealEventReplacesIt() async {
        let monitor = AgentMonitorModel()
        await monitor.discoverRunningSessions(force: true, scan: { [.init(pid: 4242, project: "social")] })
        XCTAssertEqual(monitor.state.sessions.keys.sorted(), ["discovered-4242"])
        XCTAssertEqual(monitor.dock.open.map(\.id), ["discovered-4242"], "ofiste görünür")
        monitor.ingest(ev(.userPromptSubmit, session: "gercek-1", pid: 4242).0, now: .now)
        XCTAssertEqual(monitor.state.sessions.keys.sorted(), ["gercek-1"])
        monitor.reset()
    }

    func testSystemScanFindsARealProcessNamedClaudeAndItsWorkingDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "disc-\(UUID().uuidString)", directoryHint: .isDirectory)
        let work = dir.appending(path: "proje-xyz", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appending(path: "claude")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))
        let process = Process()
        process.executableURL = link
        process.arguments = ["30"]
        process.currentDirectoryURL = work
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        usleep(300_000)
        let found = ClaudeProcessDiscovery.scan()
        let mine = found.first { $0.pid == process.processIdentifier }
        XCTAssertNotNil(mine, "adı claude olan gerçek süreç bulunmalı")
        XCTAssertEqual(mine?.project, "proje-xyz", "çalışma klasöründen proje adı")
    }
}

// MARK: Tarama uzlaştırması: durdurulmuş süreç, gerçek boşta süresi, takılı "çalışıyor", periyodik döngü

extension AgentStateTests {
    func testDiscoveryIgnoresStoppedProcessesAndReadsTranscriptName() {
        let found = ClaudeProcessDiscovery.filter([
            .init(pid: 1, argv: ["claude"], cwd: "/a/etkin", stopped: false, lastActivity: t0),
            .init(pid: 2, argv: ["claude"], cwd: "/a/ctrl-z", stopped: true, lastActivity: t0),
        ])
        XCTAssertEqual(found.map(\.pid), [1], "Ctrl+Z ile durdurulmuş süreç oturum sayılmaz")
        XCTAssertEqual(found.first?.lastActivity, t0)
        XCTAssertEqual(ClaudeProcessDiscovery.transcriptDirectoryName(forCWD: "/Users/x/Documents/websites/Adaltek/adaltek.com"), "-Users-x-Documents-websites-Adaltek-adaltek-com")
        XCTAssertEqual(ClaudeProcessDiscovery.transcriptDirectoryName(forCWD: "/Users/x/adaltek-social/adaltek_social"), "-Users-x-adaltek-social-adaltek-social")
    }

    func testTranscriptActivityComesFromRecordTimestampsNotFileModificationTime() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "proj-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appending(path: ClaudeProcessDiscovery.transcriptDirectoryName(forCWD: "/tmp/benim_proje"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Gerçek oturum: son damgalı kayıt 10 saat önce; sonrasında yalnızca damgasız durum kayıtları (Claude Code bunları sürekli yazar).
        let last = t0.addingTimeInterval(-36_000)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = [
            #"{"type":"user","timestamp":"\#(iso.string(from: last.addingTimeInterval(-600)))","message":{"role":"user","content":"merhaba"}}"#,
            #"{"type":"assistant","timestamp":"\#(iso.string(from: last))","message":{"role":"assistant","content":"selam \"timestamp\":\"2099-01-01T00:00:00.000Z\""}}"#,
            #"{"type":"last-prompt"}"#, #"{"type":"custom-title"}"#, #"{"type":"bridge-session"}"#,
        ]
        let file = dir.appending(path: "a.jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        // Dosya DEĞİŞİM zamanı "şimdi" (durum kayıtları yeni yazıldı): yine de etkinlik 10 saat öncesi olmalı.
        try FileManager.default.setAttributes([.modificationDate: t0], ofItemAtPath: file.path)
        let found = try XCTUnwrap(ClaudeProcessDiscovery.lastTranscriptActivity(cwd: "/tmp/benim_proje", projectsRoot: root))
        XCTAssertEqual(found.timeIntervalSince1970, last.timeIntervalSince1970, accuracy: 0.01, "değişim zamanı değil, son damgalı kayıt")
        XCTAssertNil(ClaudeProcessDiscovery.lastTranscriptActivity(cwd: "/tmp/yok", projectsRoot: root))
        XCTAssertNil(ClaudeProcessDiscovery.lastTranscriptActivity(cwd: "", projectsRoot: root))
    }

    func testRecordTimestampReaderHandlesHugeFilesAndTruncatedLines() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "tail-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "b.jsonl")
        let filler = String(repeating: "x", count: 4000)
        var text = #"{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":"\#(filler)"}"# + "\n"
        for _ in 0..<200 { text += #"{"type":"last-prompt","pad":"\#(filler)"}"# + "\n" }        // damgasız kayıtlar kuyruğu doldurur
        try Data(text.utf8).write(to: file)
        // Kuyruk penceresi damgalı kaydı kaçırıyorsa nil (yanlış zaman uydurmaz); yeterince büyükse bulur.
        XCTAssertNil(ClaudeProcessDiscovery.lastRecordTimestamp(in: file, tailBytes: 64 * 1024))
        let found = ClaudeProcessDiscovery.lastRecordTimestamp(in: file, tailBytes: 4 * 1024 * 1024)
        XCTAssertEqual(found?.timeIntervalSince1970, ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")?.timeIntervalSince1970)
    }

    func testPlaceholderUsesRealIdlenessSoOldIdleSessionsMinimizeAtOnce() {
        var state = AgentState()
        let now = t0.addingTimeInterval(7200)
        state.discoverSessions([.init(pid: 1, project: "eski", lastActivity: t0), .init(pid: 2, project: "taze", lastActivity: now.addingTimeInterval(-60))], now: now)
        XCTAssertEqual(state.sessions["discovered-1"]?.lastEventAt, t0, "boşta süresi keşif anından değil gerçek son etkinlikten")
        let (open, minimized) = SessionDormancy.partition(state.orderedSessions, overrides: [:], now: now)
        XCTAssertEqual(minimized.map(\.id), ["discovered-1"], "2 saattir sessiz oturum açılışta uykuda")
        XCTAssertEqual(open.map(\.id), ["discovered-2"])
    }

    func testRescanRemovesGoneOrStoppedPlaceholdersAndAdvancesActivity() {
        var state = AgentState()
        state.discoverSessions([.init(pid: 1, project: "a", lastActivity: t0), .init(pid: 2, project: "b", lastActivity: t0)], now: t0.addingTimeInterval(10))
        // Sonraki tarama: pid 2 kapandı/durduruldu; pid 1'in transkripti ilerledi.
        XCTAssertTrue(state.discoverSessions([.init(pid: 1, project: "a", lastActivity: t0.addingTimeInterval(500))], now: t0.addingTimeInterval(600)))
        XCTAssertNil(state.sessions["discovered-2"])
        XCTAssertEqual(state.sessions["discovered-1"]?.lastEventAt, t0.addingTimeInterval(500))
        XCTAssertFalse(state.discoverSessions([.init(pid: 1, project: "a", lastActivity: t0.addingTimeInterval(500))], now: t0.addingTimeInterval(700)), "değişiklik yoksa false")
    }

    func testStuckWorkingSessionBecomesIdleButBusyOnesAreLeftAlone() {
        var state = AgentState()
        state.apply(ev(.sessionStart, session: "s", pid: 7).0, now: t0)
        state.apply(ev(.preToolUse, session: "s", at: 1, tool: "Bash", pid: 7).0, now: t0.addingTimeInterval(1))
        XCTAssertEqual(state.sessions["s"]?.status, .tool("Bash"))
        // 10 dk sessizlik: henüz takılı sayılmaz.
        XCTAssertFalse(state.discoverSessions([.init(pid: 7, project: "p", lastActivity: t0)], now: t0.addingTimeInterval(600)))
        XCTAssertEqual(state.sessions["s"]?.status, .tool("Bash"))
        // 25 dk olay ve transkript yok: kapanış olayı kaçırılmış → boşta.
        XCTAssertTrue(state.discoverSessions([.init(pid: 7, project: "p", lastActivity: t0)], now: t0.addingTimeInterval(1500)))
        XCTAssertEqual(state.sessions["s"]?.status, .idle)
        // Transkript taze ise (iş sürüyor) takılı sayılmaz.
        var busy = AgentState()
        busy.apply(ev(.sessionStart, session: "b", pid: 8).0, now: t0)
        busy.apply(ev(.userPromptSubmit, session: "b", at: 1, pid: 8).0, now: t0.addingTimeInterval(1))
        XCTAssertFalse(busy.discoverSessions([.init(pid: 8, project: "p", lastActivity: t0.addingTimeInterval(1490))], now: t0.addingTimeInterval(1500)))
        XCTAssertEqual(busy.sessions["b"]?.status, .thinking)
        // Çalışan alt ajanı olan oturum takılı sayılmaz (arka plan ajanı sürüyor olabilir).
        var withSub = AgentState()
        for (e, d) in [ev(.sessionStart, session: "c", pid: 9), ev(.userPromptSubmit, session: "c", at: 1, pid: 9),
                       ev(.subagentStart, session: "c", at: 2, agentID: "a", agentType: "Explore", pid: 9)] { withSub.apply(e, now: d) }
        XCTAssertEqual(withSub.sessions["c"]?.status, .thinking)
        XCTAssertFalse(withSub.discoverSessions([.init(pid: 9, project: "p", lastActivity: t0)], now: t0.addingTimeInterval(1500)))
        XCTAssertEqual(withSub.sessions["c"]?.status, .thinking, "çalışan alt ajanı olan oturum boşta işaretlenmez")
    }

    func testIdleRealSessionIsNotMinimizedWhileItsTranscriptIsStillMoving() {
        var state = AgentState()
        state.apply(ev(.sessionStart, session: "r", pid: 5).0, now: t0)
        state.apply(ev(.stop, session: "r", at: 1, pid: 5).0, now: t0.addingTimeInterval(1))
        let now = t0.addingTimeInterval(3600)
        // Olaylar 1 saattir yok (kaçırıldı) ama transkript 1 dk önce değişti: oturum etkin, küçültülmemeli.
        state.discoverSessions([.init(pid: 5, project: "p", lastActivity: now.addingTimeInterval(-60))], now: now)
        XCTAssertEqual(SessionDormancy.partition(state.orderedSessions, overrides: [:], now: now).minimized.count, 0)
    }

    @MainActor
    func testPeriodicRescanLoopKeepsReconcilingAndStopsOnReset() async throws {
        let monitor = AgentMonitorModel()
        let calls = LockedCounter()
        monitor.startDiscoveryLoop(interval: { 0.05 }, scan: {
            let n = calls.increment()
            return n == 1 ? [.init(pid: 55, project: "ilk")] : []          // ikinci taramada süreç artık yok
        })
        for _ in 0..<60 where calls.value < 2 { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThanOrEqual(calls.value, 2, "döngü tekrar tarar")
        XCTAssertNil(monitor.state.sessions["discovered-55"], "kapanan sürecin bekleyen oturumu kalkar")
        monitor.reset()
        let after = calls.value
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertLessThanOrEqual(calls.value, after + 1, "reset döngüyü durdurur")
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    @discardableResult func increment() -> Int { lock.withLock { n += 1; return n } }
}
