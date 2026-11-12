import XCTest
@testable import Adalmon

/// OFFICE-CTRL-01: bekleyen karar deposu. Denetim kaydı YALNIZCA geçici dizine yazılır.
@MainActor
final class PendingDecisionStoreTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "decision-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func decision(session: String = "s1", agent: String? = nil, tool: String = "Bash", hash: String? = "h1", prompt: String? = "p1",
                          sent: Date? = nil, preview: String? = "SECRET-CMD rm -rf") -> PendingDecision {
        PendingDecision(request: DecisionRequest(kind: .permission, sessionID: session, agentID: agent, toolName: tool, project: "Proj",
                                                 promptID: prompt, inputHash: hash, timestamp: sent, preview: preview,
                                                 suggestions: [DecisionSuggestion(index: 0, label: "Bash(ls:*)")]))
    }

    private func event(_ name: String, session: String = "s1", agent: String? = nil, tool: String? = nil, hash: String? = nil,
                       prompt: String? = nil, at: Date? = nil) -> AgentEvent {
        AgentEvent(event: name, sessionID: session, agentID: agent, toolName: tool, timestamp: at, promptID: prompt, inputHash: hash)
    }

    func testResolveWritesVerdictOnceAndRemovesCard() {
        let store = PendingDecisionStore()
        var written: [(UUID, DecisionVerdict)] = []
        store.responder = { written.append(($0, $1)) }
        let d = decision()
        XCTAssertTrue(store.add(d))
        XCTAssertEqual(store.items.count, 1)
        store.resolve(d.id, .allow(suggestion: 0, scope: .user, mode: .acceptEdits))
        store.resolve(d.id, .deny) // geç/çift tıklama zararsız
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written.first?.1, .allow(suggestion: 0, scope: .user, mode: .acceptEdits))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testServerClosedDropsSilentlyAndEarlyCloseBlocksLateAdd() {
        let store = PendingDecisionStore()
        var released: [UUID] = []
        store.releaser = { released.append($0) }
        let d = decision()
        store.add(d)
        store.serverClosed(d.id)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(released.isEmpty, "bağlantı zaten kapalı: tekrar kapatılacak bir şey yok")
        let early = decision()
        store.serverClosed(early.id) // ana aktöre ulaşmadan kapanan bağlantı
        XCTAssertFalse(store.add(early), "kapanmış bağlantının kartı eklenmemeli")
    }

    func testPendingLimitAndSessionIDs() {
        let store = PendingDecisionStore()
        for i in 0..<PendingDecisionStore.maxPending { XCTAssertTrue(store.add(decision(session: "s\(i)"))) }
        XCTAssertFalse(store.add(decision(session: "fazla")))
        XCTAssertEqual(store.sessionIDs.count, PendingDecisionStore.maxPending)
        var changes = 0
        store.onChange = { changes += 1 }
        store.dismissAll()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(changes, 1)
    }

    func testToolResultEventsDropMatchingCardAndReleaseConnection() {
        for name in ["PostToolUse", "PostToolUseFailure", "PermissionDenied"] {
            let store = PendingDecisionStore()
            var released: [UUID] = []
            store.releaser = { released.append($0) }
            let d = decision()
            store.add(d)
            XCTAssertEqual(store.dismiss(matching: event(name, tool: "Read", hash: "h1", prompt: "p1")), 0, "\(name): başka araç")
            XCTAssertEqual(store.dismiss(matching: event(name, tool: "Bash", hash: "baska", prompt: "p1")), 0, "\(name): başka girdi")
            XCTAssertEqual(store.dismiss(matching: event(name, tool: "Bash", hash: "h1", prompt: "baska")), 0, "\(name): başka istem")
            XCTAssertEqual(store.dismiss(matching: event(name, session: "s2", tool: "Bash", hash: "h1")), 0, "\(name): başka oturum")
            XCTAssertEqual(store.dismiss(matching: event(name, agent: "a1", tool: "Bash", hash: "h1")), 0, "\(name): başka ajan")
            XCTAssertEqual(store.items.count, 1)
            XCTAssertEqual(store.dismiss(matching: event(name, tool: "Bash", hash: "h1", prompt: "p1")), 1, name)
            XCTAssertTrue(store.items.isEmpty)
            XCTAssertEqual(released, [d.id], "kart düşünce tutulan bağlantı kapatılır (betik hemen çıkar)")
        }
    }

    func testAskUserQuestionIgnoresHashMismatch() {
        let store = PendingDecisionStore()
        store.add(decision(tool: "AskUserQuestion", hash: "h1"))
        XCTAssertEqual(store.dismiss(matching: event("PostToolUse", tool: "AskUserQuestion", hash: "answers-eklendi", prompt: "p1")), 1)
    }

    func testHashAndPromptOptionalWhenEitherSideLacksThem() {
        let store = PendingDecisionStore()
        store.add(decision(hash: nil, prompt: nil))
        XCTAssertEqual(store.dismiss(matching: event("PostToolUse", tool: "Bash", hash: "x", prompt: "y")), 1)
    }

    func testSessionLevelEvents() {
        let store = PendingDecisionStore()
        store.add(decision())
        store.add(decision(agent: "a1"))
        XCTAssertEqual(store.dismiss(matching: event("Stop")), 1, "ana ajanın Stop'u yalnızca ana ajanın kartını düşürür")
        XCTAssertEqual(store.items.count, 1)
        store.add(decision())
        XCTAssertEqual(store.dismiss(matching: event("UserPromptSubmit")), 1)
        XCTAssertEqual(store.dismiss(matching: event("SubagentStop", agent: "a1")), 1)
        store.add(decision()); store.add(decision(agent: "a1"))
        XCTAssertEqual(store.dismiss(matching: event("SessionEnd")), 2, "oturum kapanınca hepsi düşer")
        XCTAssertEqual(store.dismiss(matching: event("PreToolUse", tool: "Bash")), 0)
        XCTAssertEqual(store.dismiss(matching: event("Notification")), 0)
    }

    func testEventOlderThanRequestDoesNotDropCard() {
        let store = PendingDecisionStore()
        let sent = Date()
        store.add(decision(sent: sent))
        XCTAssertEqual(store.dismiss(matching: event("PostToolUse", tool: "Bash", hash: "h1", at: sent.addingTimeInterval(-2))), 0,
                       "istekten önce üretilmiş (önceki çağrının geç gelen) olay kartı düşürmemeli")
        XCTAssertEqual(store.dismiss(matching: event("PostToolUse", tool: "Bash", hash: "h1", at: sent.addingTimeInterval(1))), 1)
    }

    // MARK: Denetim kaydı

    func testAuditLogHasMetadataOnlyAndNoContent() throws {
        let url = tmp.appending(path: "audit.jsonl")
        let store = PendingDecisionStore(auditURL: url)
        let a = decision(preview: "SECRET-PREVIEW-CONTENT"), b = decision(), c = decision()
        store.add(a); store.add(b); store.add(c)
        store.resolve(a.id, .allow(suggestion: 0, scope: .user, mode: .plan))
        store.resolve(b.id, .deny)
        store.dismiss(matching: event("Stop"))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("SECRET"), "denetim kaydı içerik taşımamalı")
        XCTAssertFalse(text.contains("Bash(ls"), "öneri metni (kural) kayda girmemeli")
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        for line in lines {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            XCTAssertTrue(Set(object.keys).isSubset(of: PendingDecisionStore.auditKeys), "\(object.keys)")
        }
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(first["verdict"] as? String, "allow")
        XCTAssertEqual(first["mode"] as? String, "plan")
        XCTAssertEqual(first["always"] as? String, "user")
        XCTAssertEqual(first["tool"] as? String, "Bash")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testAuditLogRotatesByKeepingTheTail() throws {
        let url = tmp.appending(path: "audit.jsonl")
        let entry = PendingDecisionStore.AuditEntry(ts: "t", sessionID: String(repeating: "s", count: 150), project: "P", tool: "Bash",
                                                    kind: "permission", verdict: "allow", mode: nil, always: nil)
        for _ in 0..<1400 { PendingDecisionStore.append(entry, to: url) }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        XCTAssertLessThan(size, PendingDecisionStore.auditMaxBytes + 1000)
        let count = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count
        XCTAssertLessThan(count, 1400)
        XCTAssertGreaterThan(count, 0)
    }
}
