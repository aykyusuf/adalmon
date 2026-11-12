import SwiftUI
import XCTest
@testable import Adalmon

/// OFFICE-CTRL-01: `/v1/decision` protokolü, tutulan bağlantılar ve gerçek decide.py → gerçek dinleyici → depo zinciri.
/// Her şey geçici dizinde çalışır; gerçek config.json ve ~/.claude/settings.json'a dokunulmaz, gerçek `claude` başlatılmaz.
final class AgentDecisionParserTests: XCTestCase {
    private let token = "tok-1234567890"

    private func body(_ extra: [String: Any] = [:], drop: [String] = []) -> Data {
        var object: [String: Any] = [
            "kind": "permission", "session_id": "s1", "tool_name": "Bash", "project": "Proj", "hold": 590,
            "preview": "ls -la", "input_hash": "abcd", "prompt_id": "p1",
            "suggestions": [["index": 0, "label": "Bash(ls:*)"]],
        ]
        for (k, v) in extra { object[k] = v }
        for k in drop { object[k] = nil }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func raw(_ body: Data, port: UInt16? = 5555, token: String? = nil, host: String? = nil, origin: String? = nil,
                     path: String = "/v1/decision", length: String? = nil, extraHeaders: [String] = []) -> Data {
        var head = "POST \(path) HTTP/1.1\r\n"
        if let host = host ?? port.map({ "127.0.0.1:\($0)" }) { head += "Host: \(host)\r\n" }
        head += "X-Adalmon-Token: \(token ?? self.token)\r\n"
        if let origin { head += "Origin: \(origin)\r\n" }
        head += "Content-Length: \(length ?? "\(body.count)")\r\n"
        for h in extraHeaders { head += h + "\r\n" }
        var data = Data((head + "\r\n").utf8)
        data.append(body)
        return data
    }

    func testValidPermissionRequestIsParsed() throws {
        guard case .request(let request) = AgentDecisionParser.parse(raw(body()), token: token, port: 5555) else { return XCTFail("istek bekleniyordu") }
        XCTAssertEqual(request.kind, .permission)
        XCTAssertEqual(request.sessionID, "s1")
        XCTAssertEqual(request.toolName, "Bash")
        XCTAssertEqual(request.preview, "ls -la")
        XCTAssertEqual(request.suggestions, [DecisionSuggestion(index: 0, label: "Bash(ls:*)")])
        XCTAssertEqual(request.inputHash, "abcd")
        XCTAssertEqual(request.promptID, "p1")
        XCTAssertEqual(request.hold, 590)
    }

    func testValidQuestionRequestIsParsed() throws {
        let questions: [[String: Any]] = [[
            "question": "Hangi renk?", "header": "Renk", "multiSelect": true,
            "options": [["label": "Mavi", "description": "serin"], ["label": "Kırmızı"], ["label": "Mavi"]],
        ]]
        guard case .request(let request) = AgentDecisionParser.parse(
            raw(body(["kind": "question", "tool_name": "AskUserQuestion", "questions": questions], drop: ["preview", "suggestions"])),
            token: token, port: 5555) else { return XCTFail("istek bekleniyordu") }
        XCTAssertEqual(request.kind, .question)
        XCTAssertEqual(request.questions.count, 1)
        XCTAssertTrue(request.questions[0].multiSelect)
        XCTAssertEqual(request.questions[0].options.map(\.label), ["Mavi", "Kırmızı"], "yinelenen etiket atılır")
        XCTAssertNil(request.preview)
    }

    func testQuestionWithoutValidQuestionsIsRejected() {
        let bad: [[String: Any]] = [["question": "Boş", "options": []]]
        XCTAssertEqual(AgentDecisionParser.parse(raw(body(["kind": "question", "questions": bad])), token: token, port: 5555), .reject(400))
        XCTAssertEqual(AgentDecisionParser.parse(raw(body(["kind": "question"])), token: token, port: 5555), .reject(400))
    }

    func testHeaderRules() {
        let b = body()
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, token: "yanlis"), token: token, port: 5555), .reject(401))
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, host: "evil.example:5555"), token: token, port: 5555), .reject(421), "DNS rebinding")
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, host: "127.0.0.1:1"), token: token, port: 5555), .reject(421))
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, port: nil), token: token, port: 5555), .reject(421), "Host yok")
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, origin: "http://evil.example"), token: token, port: 5555), .reject(403), "tarayıcıdan gelemez")
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, path: "/v1/decision?x=1"), token: token, port: 5555), .reject(400))
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, extraHeaders: ["Transfer-Encoding: chunked"]), token: token, port: 5555), .reject(400))
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, extraHeaders: ["Content-Length: 3"]), token: token, port: 5555), .reject(400), "çift Content-Length")
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, token: ""), token: "", port: 5555), .reject(401), "boş token asla kabul edilmez")
    }

    func testSizeAndFraming() {
        let b = body()
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, length: "99999"), token: token, port: 5555), .reject(413))
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, length: "abc"), token: token, port: 5555), .reject(400))
        XCTAssertEqual(AgentDecisionParser.parse(raw(b, length: "\(b.count + 10)"), token: token, port: 5555), .needMore)
        XCTAssertEqual(AgentDecisionParser.parse(Data("POST /v1/decision HTTP/1.1\r\nHost: x".utf8), token: token, port: 5555), .needMore)
        XCTAssertEqual(AgentDecisionParser.parse(Data(repeating: 65, count: 9000), token: token, port: 5555), .reject(431))
        XCTAssertEqual(AgentDecisionParser.parse(raw(Data("not json".utf8)), token: token, port: 5555), .reject(400))
        XCTAssertEqual(AgentDecisionParser.parse(raw(body(drop: ["session_id"])), token: token, port: 5555), .reject(400))
        XCTAssertEqual(AgentDecisionParser.parse(raw(body(["kind": "approve"])), token: token, port: 5555), .reject(400))
    }

    func testRoutingPeekOnlyMatchesDecisionRequests() {
        XCTAssertTrue(AgentDecisionParser.isDecisionRequest(raw(body())))
        XCTAssertFalse(AgentDecisionParser.isDecisionRequest(Data("POST /v1/event HTTP/1.1\r\n".utf8)))
        XCTAssertFalse(AgentDecisionParser.isDecisionRequest(Data("GET /v1/decision HTTP/1.1\r\n".utf8)))
        XCTAssertFalse(AgentDecisionParser.isDecisionRequest(Data("POST /v1/decisionx HTTP/1.1\r\n".utf8)))
    }

    func testFieldLimitsAndSanitizing() throws {
        let long = String(repeating: "x", count: 5000)
        let suggestions: [[String: Any]] = (0..<12).map { ["index": $0, "label": "kural \($0)"] }
        guard case .request(let request) = AgentDecisionParser.parse(
            raw(body(["preview": "a\u{0007}b\n" + long, "suggestions": suggestions, "hold": 99999, "session_id": "s\u{0000}1", "bilinmeyen": "SECRET"])),
            token: token, port: 5555) else { return XCTFail() }
        XCTAssertEqual(request.preview?.count, DecisionLimits.maxPreview)
        XCTAssertTrue(request.preview?.hasPrefix("ab\nxxx") == true, "kontrol karakteri atılır, satır sonu kalır")
        XCTAssertEqual(request.suggestions.count, DecisionLimits.maxSuggestions)
        XCTAssertEqual(request.hold, DecisionLimits.maxHold, "bekleme üst sınırı hook zaman aşımının altında")
        XCTAssertEqual(request.sessionID, "s1")
        XCTAssertFalse(Mirror(reflecting: request).children.contains { "\($0.value)".contains("SECRET") }, "beyaz liste dışı anahtar okunmaz")
    }

    func testCleanTruncatesByCodePointsAndTrimsLikePython() {
        // 7 kod noktalı tek bir Character (aile emojisi): Character sayarak kırpmak 2 Character = 14 kod noktası bırakırdı.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        let cut = DecisionRequest.clean(family + family, max: 8)
        XCTAssertEqual(cut?.unicodeScalars.count, 8)
        XCTAssertEqual(DecisionRequest.clean("\u{2028}x\u{2029}\u{00A0}", max: 10), "x", "Python str.strip() ile aynı boşluklar")
        XCTAssertEqual(DecisionRequest.clean("\u{200B}x", max: 10), "\u{200B}x", "sıfır genişlikli boşluk Python'da boşluk değildir")
        XCTAssertNil(DecisionRequest.clean("\u{2028} \u{3000}", max: 10))
        XCTAssertEqual(DecisionRequest.clean("a\u{0007}b", max: 10), "ab")
        XCTAssertEqual(DecisionRequest.clean(" a\nb\t ", max: 10, multiline: true), "a\nb")
    }

    func testVerdictWireFormatAndRelease() throws {
        func json(_ v: DecisionVerdict) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(v.wireJSON)) as? [String: Any]) }
        XCTAssertEqual(try json(.deny)["verdict"] as? String, "deny")
        let allow = try json(.allow(suggestion: 2, scope: .user, mode: .acceptEdits))
        XCTAssertEqual(allow["verdict"] as? String, "allow")
        XCTAssertEqual(allow["suggestion"] as? Int, 2)
        XCTAssertEqual(allow["scope"] as? String, "user")
        XCTAssertEqual(allow["mode"] as? String, "acceptEdits")
        XCTAssertEqual((try json(.answer(["q": ["a", "b"]]))["answers"] as? [String: [String]])?["q"], ["a", "b"])
        XCTAssertNil(DecisionVerdict.release.wireJSON)
        XCTAssertTrue(String(decoding: AgentDecisionParser.response(for: .release), as: UTF8.self).hasPrefix("HTTP/1.1 204"))
        XCTAssertTrue(String(decoding: AgentDecisionParser.response(for: .deny), as: UTF8.self).hasPrefix("HTTP/1.1 200"))
        XCTAssertFalse(DecisionPermissionMode.allCases.map(\.rawValue).contains("bypassPermissions"), "bypass asla sunulmaz")
        XCTAssertTrue(DecisionVerdict.allow(suggestion: nil, scope: .session, mode: nil).wireJSON.map { String(decoding: $0, as: UTF8.self) }?.contains("bypass") == false)
    }

    func testEventTypeCarriesNoContentKeys() {
        let forbidden: Set<String> = ["tool_input", "questions", "answers", "input_preview", "preview", "suggestions", "permission_suggestions", "prompt", "command"]
        XCTAssertTrue(AgentEvent.allowedKeys.isDisjoint(with: forbidden))
        let event = AgentEvent(json: Data(#"{"event":"PostToolUse","session_id":"s","tool_input":{"command":"SECRET"},"preview":"SECRET","input_hash":"abc","prompt_id":"p"}"#.utf8))
        XCTAssertEqual(event?.inputHash, "abc")
        XCTAssertFalse("\(String(describing: event))".contains("SECRET"))
    }
}

// MARK: Tutulan bağlantılar (gerçek 127.0.0.1 dinleyicisi)

final class AgentDecisionServerTests: XCTestCase {
    private let token = "tok-held-0123456789"

    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [T] = []
        func add(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
        var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
    }
    private final class PortBox: @unchecked Sendable {
        private let lock = NSLock()
        private var state = AgentEventServer.State.stopped
        func set(_ s: AgentEventServer.State) { lock.lock(); state = s; lock.unlock() }
        var value: AgentEventServer.State { lock.lock(); defer { lock.unlock() }; return state }
    }

    private func start(events: Box<AgentEvent>, decisions: Box<(DecisionRequest, UUID)>, closed: Box<UUID>) async throws -> (AgentEventServer, UInt16) {
        let state = PortBox()
        let ready = expectation(description: "ready")
        ready.assertForOverFulfill = false
        let server = AgentEventServer(token: token, onEvent: { events.add($0) }, onState: { s in
            state.set(s)
            if case .running = s { ready.fulfill() }
        }, onDecision: { decisions.add(($0, $1)) }, onHeldClosed: { closed.add($0) })
        server.start(preferredPort: nil)
        await fulfillment(of: [ready], timeout: 5)
        guard case .running(let port) = state.value else { throw XCTSkip("dinleyici başlatılamadı: \(state.value)") }
        return (server, port)
    }

    private func decisionRequest(_ port: UInt16, session: String = "s1", token: String? = nil, timeout: TimeInterval = 8) -> URLRequest {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/decision")!)
        req.httpMethod = "POST"
        req.setValue(token ?? self.token, forHTTPHeaderField: "X-Adalmon-Token")
        req.httpBody = Data(#"{"kind":"permission","session_id":"\#(session)","tool_name":"Bash","preview":"ls"}"#.utf8)
        req.timeoutInterval = timeout
        return req
    }

    private func eventually(_ what: String, timeout: TimeInterval = 5, _ condition: () async -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if await condition() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail("zaman aşımı: \(what)")
    }

    func testHeldConnectionReceivesVerdictOnTheSameConnection() async throws {
        let events = Box<AgentEvent>(), decisions = Box<(DecisionRequest, UUID)>(), closed = Box<UUID>()
        let (server, port) = try await start(events: events, decisions: decisions, closed: closed)
        defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)
        let request = decisionRequest(port)
        let task = Task { try await session.data(for: request) }
        try await eventually("karar isteği ulaştı") { decisions.all.count == 1 }
        XCTAssertEqual(decisions.all.first?.0.preview, "ls")
        XCTAssertEqual(decisions.all.first?.0.sessionID, "s1")
        let heldWhileWaiting = await server.heldCount()
        XCTAssertEqual(heldWhileWaiting, 1)
        // Karar verilene kadar yanıt gelmez (5 sn'lik zaman aşımına rağmen tutulur).
        try await Task.sleep(for: .milliseconds(300))
        server.respondHeld(decisions.all[0].1, response: AgentDecisionParser.response(for: .deny))
        let (data, response) = try await task.value
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["verdict"] as? String, "deny")
        try await eventually("bağlantı bırakıldı") { await server.heldCount() == 0 }
        XCTAssertTrue(closed.all.isEmpty, "yanıtlanan bağlantı için 'kapandı' bildirimi gelmez")
    }

    func testRealTimeoutDoesNotCutHeldConnection() async throws {
        let events = Box<AgentEvent>(), decisions = Box<(DecisionRequest, UUID)>(), closed = Box<UUID>()
        let (server, port) = try await start(events: events, decisions: decisions, closed: closed)
        defer { server.stop() }
        let request = decisionRequest(port, timeout: 20)
        let task = Task { try await URLSession(configuration: .ephemeral).data(for: request) }
        try await eventually("istek ulaştı") { decisions.all.count == 1 }
        try await Task.sleep(for: .seconds(6)) // olay bağlantılarının 5 sn'lik zaman aşımını aşar
        let stillHeld = await server.heldCount()
        XCTAssertEqual(stillHeld, 1, "tutulan bağlantı 5 sn zaman aşımından muaf")
        server.respondHeld(decisions.all[0].1, response: AgentDecisionParser.response(for: .release))
        let (_, response) = try await task.value
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
    }

    func testClientClosingNotifiesAndFreesTheSlot() async throws {
        let events = Box<AgentEvent>(), decisions = Box<(DecisionRequest, UUID)>(), closed = Box<UUID>()
        let (server, port) = try await start(events: events, decisions: decisions, closed: closed)
        defer { server.stop() }
        let request = decisionRequest(port)
        let task = Task { try await URLSession(configuration: .ephemeral).data(for: request) }
        try await eventually("istek ulaştı") { decisions.all.count == 1 }
        task.cancel() // betik öldü / zaman aşımı
        try await eventually("kapanış bildirildi") { closed.all.count == 1 }
        XCTAssertEqual(closed.all.first, decisions.all.first?.1)
        let remaining = await server.heldCount()
        XCTAssertEqual(remaining, 0)
    }

    func testHeldCapDoesNotStarveEventForwarder() async throws {
        let events = Box<AgentEvent>(), decisions = Box<(DecisionRequest, UUID)>(), closed = Box<UUID>()
        let (server, port) = try await start(events: events, decisions: decisions, closed: closed)
        defer { server.stop() }
        var tasks: [Task<(Data, URLResponse), Error>] = []
        for i in 0..<AgentEventServer.maxHeld {
            let request = decisionRequest(port, session: "s\(i)")
            tasks.append(Task { try await URLSession(configuration: .ephemeral).data(for: request) })
        }
        try await eventually("8 tutulan bağlantı") { decisions.all.count == AgentEventServer.maxHeld }
        // 9. istek: üst sınır → 429.
        let (_, over) = try await URLSession(configuration: .ephemeral).data(for: decisionRequest(port, session: "fazla"))
        XCTAssertEqual((over as? HTTPURLResponse)?.statusCode, 429)
        // Olay iletici hâlâ çalışır (16 bağlantı payına tutulanlar sayılmaz).
        var event = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/event")!)
        event.httpMethod = "POST"
        event.setValue(token, forHTTPHeaderField: "X-Adalmon-Token")
        event.httpBody = Data(#"{"event":"Stop","session_id":"s0"}"#.utf8)
        let (_, ok) = try await URLSession(configuration: .ephemeral).data(for: event)
        XCTAssertEqual((ok as? HTTPURLResponse)?.statusCode, 204)
        XCTAssertEqual(events.all.map(\.event), ["Stop"])
        for (request, id) in decisions.all { _ = request; server.respondHeld(id, response: AgentDecisionParser.response(for: .release)) }
        for task in tasks { _ = try await task.value }
    }

    func testBadTokenAndNoApproveRoute() async throws {
        let events = Box<AgentEvent>(), decisions = Box<(DecisionRequest, UUID)>(), closed = Box<UUID>()
        let (server, port) = try await start(events: events, decisions: decisions, closed: closed)
        defer { server.stop() }
        let (_, bad) = try await URLSession(configuration: .ephemeral).data(for: decisionRequest(port, token: "yanlis"))
        XCTAssertEqual((bad as? HTTPURLResponse)?.statusCode, 401)
        XCTAssertTrue(decisions.all.isEmpty)
        for path in ["/v1/decision/approve", "/v1/approve", "/v1/decision/allow"] {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
            req.httpMethod = "POST"
            req.setValue(token, forHTTPHeaderField: "X-Adalmon-Token")
            req.httpBody = Data(#"{"verdict":"allow"}"#.utf8)
            let (_, response) = try await URLSession(configuration: .ephemeral).data(for: req)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404, path)
        }
        XCTAssertTrue(decisions.all.isEmpty)
    }
}

// MARK: Uçtan uca (gerçek decide.py → gerçek dinleyici → AgentService/PendingDecisionStore)

@MainActor
final class AgentDecisionEndToEndTests: XCTestCase {
    private var tmp: URL!
    private var generator: AgentPluginGenerator!
    private var service: AgentService!
    private var defaults: UserDefaults!
    private var suite = ""
    private var realConfigBefore: Data?
    private var realSettingsBefore: Data?
    private let realConfig = AgentPluginGenerator().configURL
    private let realSettings = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")

    override func setUp() async throws {
        try XCTSkipUnless(AgentPluginGenerator.pythonAvailable(), "python3 yok")
        realConfigBefore = try? Data(contentsOf: realConfig)
        realSettingsBefore = try? Data(contentsOf: realSettings)
        tmp = FileManager.default.temporaryDirectory.appending(path: "decision-e2e-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        suite = "AgentDecisionE2E-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let prefs = Preferences(defaults: defaults)
        prefs.agentsEnabled = true
        generator = AgentPluginGenerator(root: tmp, usesPython: true)
        try generator.write(port: 1, token: "gecici")
        service = AgentService(prefs: prefs, installer: AgentPluginInstaller(generator: generator))
        service.discoveryEnabled = false
        service.setControlEnabled(true)
        service.apply()
        for _ in 0..<50 where service.port == nil { try await Task.sleep(for: .milliseconds(100)) }
        _ = try XCTUnwrap(service.port, "dinleyici başlamalı")
        try await Task.sleep(for: .milliseconds(300)) // config.json yazımı
    }

    override func tearDown() async throws {
        service?.setEnabled(false)
        defaults?.removePersistentDomain(forName: suite)
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertEqual(try? Data(contentsOf: realConfig), realConfigBefore, "test gerçek config.json'a dokunmamalı")
        XCTAssertEqual(try? Data(contentsOf: realSettings), realSettingsBefore, "test ~/.claude/settings.json'a dokunmamalı")
    }

    private func eventually(_ what: String, timeout: TimeInterval = 8, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if condition() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail("zaman aşımı: \(what)")
    }

    private func openSession(_ id: String = "live-1") {
        service.monitor.ingest(AgentEvent(event: "SessionStart", sessionID: id, project: "Proj"))
    }

    /// decide.py'yi gerçek süreç olarak çalıştırır (ana aktörü bloklamaz); çıktı + süre döner.
    private func runDecide(_ stdin: String, config: URL? = nil) -> Task<(output: String, status: Int32), Never> {
        let script = generator.decideScriptURL
        let configPath = (config ?? generator.configURL).path
        return Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/python3")
            process.arguments = ["-I", script.path]
            process.environment = ProcessInfo.processInfo.environment.merging(["ADALMON_AGENTS_CONFIG": configPath]) { $1 }
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return ("", -1) }
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (String(decoding: data, as: UTF8.self), process.terminationStatus)
        }
    }

    private func permissionInput(session: String = "live-1", command: String = "npm test", extra: String = "") -> String {
        """
        {"hook_event_name":"PermissionRequest","session_id":"\(session)","cwd":"/Users/x/Proj","permission_mode":"default",
         "tool_name":"Bash","tool_input":{"command":"\(command)"},"prompt_id":"pr-1",
         "permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm test"}],"behavior":"allow","destination":"localSettings"}]\(extra)}
        """
    }

    private func decoded(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], "çıktı JSON değil: \(text)")
    }

    func testAllowAlwaysUserWithModeRoundTrip() async throws {
        openSession()
        let run = runDecide(permissionInput())
        try await eventually("kart göründü") { service.decisions.items.count == 1 }
        let card = try XCTUnwrap(service.decisions.items.first)
        XCTAssertEqual(card.request.toolName, "Bash")
        XCTAssertEqual(card.request.preview, "npm test")
        XCTAssertEqual(card.request.project, "Proj")
        XCTAssertEqual(card.request.suggestions.map(\.label), ["Bash(npm test)"])
        XCTAssertTrue(service.monitor.attention.contains("live-1"), "bekleyen karar oturumu dikkat istiyor sayar")
        service.respond(card.id, .allow(suggestion: 0, scope: .user, mode: .acceptEdits))
        let result = await run.value
        XCTAssertEqual(result.status, 0)
        let decision = try XCTUnwrap(((try decoded(result.output))["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        let updated = try XCTUnwrap(decision["updatedPermissions"] as? [[String: Any]])
        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(updated[0]["destination"] as? String, "userSettings", "Hep izin ver GLOBAL: Claude Code kendisi yazar")
        XCTAssertEqual(updated[0]["type"] as? String, "addRules")
        XCTAssertEqual(updated[1]["type"] as? String, "setMode")
        XCTAssertEqual(updated[1]["mode"] as? String, "acceptEdits")
        XCTAssertTrue(service.decisions.items.isEmpty)
        XCTAssertFalse(service.monitor.attention.contains("live-1"))
    }

    func testDenyAndReleaseAndSessionScope() async throws {
        openSession()
        var run = runDecide(permissionInput())
        try await eventually("kart 1") { service.decisions.items.count == 1 }
        service.respond(service.decisions.items[0].id, .deny)
        var result = await run.value
        var decision = try XCTUnwrap(((try decoded(result.output))["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "deny")

        run = runDecide(permissionInput())
        try await eventually("kart 2") { service.decisions.items.count == 1 }
        service.respond(service.decisions.items[0].id, .release)
        result = await run.value
        XCTAssertEqual(result.output, "", "terminale bırakılırsa çıktı yok")
        XCTAssertEqual(result.status, 0)

        run = runDecide(permissionInput())
        try await eventually("kart 3") { service.decisions.items.count == 1 }
        service.respond(service.decisions.items[0].id, .allow(suggestion: 0, scope: .session, mode: nil))
        result = await run.value
        decision = try XCTUnwrap(((try decoded(result.output))["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        XCTAssertEqual((decision["updatedPermissions"] as? [[String: Any]])?.first?["destination"] as? String, "session")
    }

    func testQuestionAnswersMultiSelectJoinedWithCommaSpace() async throws {
        openSession()
        let input = """
        {"hook_event_name":"PermissionRequest","session_id":"live-1","cwd":"/Users/x/Proj","tool_name":"AskUserQuestion","prompt_id":"pr-1",
         "tool_input":{"questions":[
           {"question":"Pick a color","header":"Color","multiSelect":false,"options":[{"label":"Blue","description":"b"},{"label":"Red","description":"r"}]},
           {"question":"Pick fruits","header":"Fruit","multiSelect":true,"options":[{"label":"Apple","description":"a"},{"label":"Banana","description":"b"},{"label":"Cherry","description":"c"}]}]}}
        """
        let run = runDecide(input)
        try await eventually("soru kartı") { service.decisions.items.count == 1 }
        let card = try XCTUnwrap(service.decisions.items.first)
        XCTAssertEqual(card.request.kind, .question)
        XCTAssertEqual(card.request.questions.map(\.question), ["Pick a color", "Pick fruits"])
        service.respond(card.id, .answer(["Pick a color": ["Blue"], "Pick fruits": ["Cherry", "Apple"]]))
        let result = await run.value
        let decision = try XCTUnwrap(((try decoded(result.output))["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        let updated = try XCTUnwrap(decision["updatedInput"] as? [String: Any])
        XCTAssertEqual((updated["questions"] as? [[String: Any]])?.count, 2)
        let answers = try XCTUnwrap(updated["answers"] as? [String: String])
        XCTAssertEqual(answers, ["Pick a color": "Blue", "Pick fruits": "Apple, Cherry"])
    }

    func testToolResultEventDropsCardAndClosesHeldConnectionPromptly() async throws {
        openSession()
        let run = runDecide(permissionInput())
        try await eventually("kart göründü") { service.decisions.items.count == 1 }
        let hash = try XCTUnwrap(service.decisions.items.first?.request.inputHash)
        let started = Date()
        // Kullanıcı terminalde cevapladı: araç çalıştı, PostToolUse olayı aynı oturum/araç/girdi özetiyle geldi.
        // (Gerçek zincirde bunu forward.py üretir; burada olay doğrudan izleyiciye + depoya verilir.)
        let event = AgentEvent(event: "PostToolUse", sessionID: "live-1", toolName: "Bash", timestamp: .now.addingTimeInterval(1), promptID: "pr-1", inputHash: hash)
        service.monitor.ingest(event)
        XCTAssertEqual(service.decisions.dismiss(matching: event), 1)
        let result = await run.value
        XCTAssertEqual(result.output, "", "kart düşünce betik çıktısız çıkar")
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "bağlantı kapatılınca betik cap'i beklemez")
        XCTAssertTrue(service.decisions.items.isEmpty)
    }

    func testUnknownSessionAndDisabledControlFailOpen() async throws {
        // Bilinmeyen oturum: dinleyici 403 → betik çıktısız çıkar, kart oluşmaz.
        var result = await runDecide(permissionInput(session: "hayali")).value
        XCTAssertEqual(result.output, "")
        XCTAssertTrue(service.decisions.items.isEmpty)
        // Ofisten cevapla kapalı: betik config'i okuyup ağ kullanmadan çıkar.
        openSession()
        service.setControlEnabled(false)
        XCTAssertFalse(generator.readControlEnabled())
        result = await runDecide(permissionInput()).value
        XCTAssertEqual(result.output, "")
        XCTAssertTrue(service.decisions.items.isEmpty)
        // Sunucuyu kapatma: bekleyen kart varsa düşer.
        service.setControlEnabled(true)
        let run = runDecide(permissionInput())
        try await eventually("kart göründü") { service.decisions.items.count == 1 }
        service.setControlEnabled(false)
        XCTAssertTrue(service.decisions.items.isEmpty, "özellik kapanınca bekleyen kartlar düşer")
        result = await run.value
        XCTAssertEqual(result.output, "")
    }

    func testListenerStopDropsCardsAndScriptExits() async throws {
        openSession()
        let run = runDecide(permissionInput())
        try await eventually("kart göründü") { service.decisions.items.count == 1 }
        service.setEnabled(false)
        XCTAssertTrue(service.decisions.items.isEmpty)
        let result = await run.value
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.status, 0)
    }

    func testListenerStopFailureAndQuitClearControlFlagAndRestartRestoresPreference() async throws {
        XCTAssertTrue(generator.readControlEnabled(), "dinleyici çalışırken tercih config.json'a yazılır")
        service.setEnabled(false)
        XCTAssertFalse(generator.readControlEnabled(), "dinleyici durunca betik ölü porta gitmesin")
        XCTAssertNotNil(generator.readConfig(), "port/token dosyada kalır")
        // Dinleyici kapalıyken açılan tercih dosyaya yazılmaz; dinleyici .running olunca geri yazılır.
        service.setControlEnabled(true)
        XCTAssertFalse(generator.readControlEnabled())
        service.setEnabled(true)
        try await eventually("dinleyici") { service.port != nil }
        try await eventually("tercih geri yazıldı") { generator.readControlEnabled() }
        // Kullanıcı tercihi kapalıysa yeniden başlatmada da kapalı kalır.
        service.setControlEnabled(false)
        service.setEnabled(false)
        service.setEnabled(true)
        try await eventually("dinleyici (2)") { service.port != nil }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(generator.readControlEnabled())
        // Uygulama kapanırken.
        service.setControlEnabled(true)
        XCTAssertTrue(generator.readControlEnabled())
        service.prepareForTermination()
        XCTAssertFalse(generator.readControlEnabled())
    }

    func testDecisionContentNeverReachesEventsStateOrWebSnapshot() async throws {
        openSession()
        let marker = "SECRET-MARKER-9f3a"
        let run = runDecide(permissionInput(command: marker))
        try await eventually("kart göründü") { service.decisions.items.count == 1 }
        XCTAssertEqual(service.decisions.items.first?.request.preview, marker)
        // Olay durumu (AgentState) ve web görüntüsü içerik taşımaz.
        XCTAssertFalse("\(service.monitor.state)".contains(marker))
        let builder = AgentWebSnapshotBuilder(seats: [:])
        let json = builder.snapshot(sessions: service.monitor.state.orderedSessions)
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains(marker))
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("npm test"))
        service.respond(service.decisions.items[0].id, .release)
        _ = await run.value
    }
}

// MARK: Kart görünümü (çizim duman testi)

@MainActor
final class OfficeDecisionViewTests: XCTestCase {
    private func card() -> OfficeDetailCard {
        OfficeDetailCard(memberID: "s1", isSession: true, title: "Proje", roleName: "ana ajan", badge: .opus, status: "izin bekliyor", tool: nil,
                         startedAt: nil, parentTitle: nil, subagentCount: 0, children: [])
    }

    private func render(_ decision: PendingDecision) throws -> CGSize {
        let view = OfficeCardView(card: card(), decisions: [decision], onDecide: { _, _ in }, close: {})
            .padding(16).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "kart çizilemedi")
        return CGSize(width: image.width, height: image.height)
    }

    func testPermissionAndQuestionCardsRender() throws {
        let permission = PendingDecision(request: DecisionRequest(kind: .permission, sessionID: "s1", toolName: "Bash", preview: "npm test",
                                                                   suggestions: [DecisionSuggestion(index: 0, label: "Bash(npm test)")]))
        let question = PendingDecision(request: DecisionRequest(kind: .question, sessionID: "s1", toolName: "AskUserQuestion", questions: [
            DecisionQuestion(question: "Hangi renk?", header: "Renk", multiSelect: true, options: [.init(label: "Mavi", description: "serin"), .init(label: "Kırmızı", description: nil)]),
        ]))
        XCTAssertGreaterThan(try render(permission).width, 300)
        XCTAssertGreaterThan(try render(question).height, 100)
    }

    func testRemainingText() {
        let now = Date()
        XCTAssertEqual(OfficeDecisionView.remaining(until: now.addingTimeInterval(125), now: now), "kalan 2:05")
        XCTAssertEqual(OfficeDecisionView.remaining(until: now.addingTimeInterval(-5), now: now), "kalan 0:00")
    }
}
