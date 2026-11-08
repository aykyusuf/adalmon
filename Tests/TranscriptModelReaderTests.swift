import XCTest
@testable import Adalmon

final class TranscriptModelReaderTests: XCTestCase {
    private func line(_ model: String?, type: String = "assistant") -> String {
        let m = model.map { ",\"model\":\"\($0)\"" } ?? ""
        return "{\"type\":\"\(type)\",\"message\":{\"role\":\"\(type)\"\(m),\"content\":[{\"type\":\"text\",\"text\":\"x\"}]}}"
    }

    private func tail(_ lines: [String], truncated: Bool = false) -> TranscriptTail {
        TranscriptTail(data: Data(lines.joined(separator: "\n").utf8), isTruncated: truncated)
    }

    func testFindsModel() {
        XCTAssertEqual(TranscriptModelParser.latestModel(in: tail([line(nil, type: "user"), line("claude-opus-4-8")])), "claude-opus-4-8")
    }

    func testMultipleModelsLastWins() {
        let t = tail([line("claude-sonnet-4-6"), line(nil, type: "user"), line("claude-haiku-4-5"), line(nil, type: "user")])
        XCTAssertEqual(TranscriptModelParser.latestModel(in: t), "claude-haiku-4-5")
    }

    func testMalformedLinesSkipped() {
        let t = tail([line("claude-opus-4-8"), "{\"type\":\"assistant\",\"message\":{\"model\":\"claude-x", "not json \"model\" \"assistant\"", ""])
        XCTAssertEqual(TranscriptModelParser.latestModel(in: t), "claude-opus-4-8")
    }

    func testNoModelField() {
        XCTAssertNil(TranscriptModelParser.latestModel(in: tail([line(nil), line(nil, type: "user")])))
        XCTAssertNil(TranscriptModelParser.latestModel(in: tail([])))
    }

    func testOnlyAssistantMessagesCount() {
        XCTAssertNil(TranscriptModelParser.latestModel(in: tail([line("claude-opus-4-8", type: "user")])))
    }

    func testInvalidValuesRejectedAndOlderValidOneUsed() {
        for bad in ["<synthetic>", "gpt-5", "claude opus", "claude/../x", String(repeating: "a", count: 70), "claude-" + String(repeating: "a", count: 60), ""] {
            XCTAssertNil(TranscriptModelParser.latestModel(in: tail([line(bad)])), bad)
        }
        let t = tail([line("claude-sonnet-4-6"), line("<synthetic>")])
        XCTAssertEqual(TranscriptModelParser.latestModel(in: t), "claude-sonnet-4-6")
        XCTAssertTrue(TranscriptModelParser.isValidModel("claude-opus-4-8[1m]"))
        XCTAssertTrue(TranscriptModelParser.isValidModel("claude-sonnet-4-6:beta.1_x"))
        XCTAssertFalse(TranscriptModelParser.isValidModel("Claude-opus"))
    }

    func testHugeLineIgnoredWithoutBreakingOthers() {
        let huge = "{\"type\":\"assistant\",\"message\":{\"model\":\"claude-opus-4-8\",\"content\":\"" + String(repeating: "z", count: 300_000) + "\"}}"
        // Çok büyük satır yarım (kuyruk içinde başlangıcı yok): atılır, öncesi görünmez.
        let cut = TranscriptTail(data: Data(huge.suffix(128 * 1024).utf8), isTruncated: true)
        XCTAssertNil(TranscriptModelParser.latestModel(in: cut))
        // Kuyruk içine tam sığan satırdan sonra gelen bozuk satır modeli bozmaz.
        XCTAssertEqual(TranscriptModelParser.latestModel(in: tail([line("claude-haiku-4-5"), String(repeating: "q", count: 50_000)])), "claude-haiku-4-5")
    }

    func testTruncatedTailDropsPartialFirstLine() {
        // İlk (yarım) satır geçerli görünse bile atılır.
        let partial = "tial\",\"model\":\"claude-opus-4-8\",\"type\":\"assistant\"}}"
        XCTAssertNil(TranscriptModelParser.latestModel(in: tail([partial], truncated: true)))
        XCTAssertEqual(TranscriptModelParser.latestModel(in: tail([partial, line("claude-fable-1")], truncated: true)), "claude-fable-1")
        XCTAssertNotNil(TranscriptModelParser.latestModel(in: tail([line("claude-fable-1")], truncated: false)))
    }

    func testSessionIDValidation() {
        XCTAssertTrue(TranscriptModelParser.isValidSessionID("0fa1b2c3-1111-2222-3333-444455556666"))
        for bad in ["", "..", "../x", "a/b", "a.b", "a b", "a\u{0}b", "é", String(repeating: "a", count: 65), "a\nb", "~"] {
            XCTAssertFalse(TranscriptModelParser.isValidSessionID(bad), bad)
        }
    }

    func testBadgeMapping() {
        XCTAssertEqual(AgentModelBadge(modelID: "claude-opus-4-8"), .opus)
        XCTAssertEqual(AgentModelBadge(modelID: "claude-sonnet-4-6"), .sonnet)
        XCTAssertEqual(AgentModelBadge(modelID: "claude-haiku-4-5"), .haiku)
        XCTAssertEqual(AgentModelBadge(modelID: "claude-fable-1"), .fable)
    }

    // MARK: Gerçek okuyucu (yalnızca geçici dizin)

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("adalmon-tx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func write(_ text: String, project: String = "-proj-a", id: String) throws -> URL {
        let dir = tmp.appendingPathComponent(project, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(id).jsonl")
        try Data(text.utf8).write(to: url)
        return url
    }

    func testRealReaderFindsFileInProjectDirectory() throws {
        _ = try write(line("claude-sonnet-4-6") + "\n" + line("claude-opus-4-8") + "\n", id: "abc-123")
        let resolver = TranscriptModelResolver(reader: ClaudeProjectsTailReader(root: tmp))
        XCTAssertEqual(resolver.latestModel(sessionID: "abc-123"), "claude-opus-4-8")
        XCTAssertNil(resolver.latestModel(sessionID: "missing"))
        XCTAssertNil(resolver.latestModel(sessionID: "../abc-123"))
    }

    func testRealReaderReadsOnlyTailOfLongFile() throws {
        let filler = line("claude-haiku-4-5") + "\n"
        let body = String(repeating: "{\"type\":\"user\",\"x\":\"" + String(repeating: "y", count: 900) + "\"}\n", count: 400) // ~360 KB
        _ = try write(filler + body + line("claude-opus-4-8") + "\n", id: "long")
        let reader = ClaudeProjectsTailReader(root: tmp)
        let tail = try XCTUnwrap(reader.readTail(sessionID: "long", maxBytes: TranscriptModelParser.tailBytes))
        XCTAssertLessThanOrEqual(tail.data.count, TranscriptModelParser.tailBytes)
        XCTAssertTrue(tail.isTruncated)
        XCTAssertEqual(TranscriptModelResolver(reader: reader).latestModel(sessionID: "long"), "claude-opus-4-8")
        // Eski model kuyruğun dışında kaldığı için görünmez.
        _ = try write(filler + body, project: "-proj-b", id: "old")
        XCTAssertNil(TranscriptModelResolver(reader: reader).latestModel(sessionID: "old"))
    }

    func testRealReaderDoesNotFollowSymlinks() throws {
        let outside = tmp.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let real = outside.appendingPathComponent("real.jsonl")
        try Data((line("claude-opus-4-8") + "\n").utf8).write(to: real)
        let projects = tmp.appendingPathComponent("projects", isDirectory: true)
        let dir = projects.appendingPathComponent("-p", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("linked.jsonl"), withDestinationURL: real)
        try FileManager.default.createSymbolicLink(at: projects.appendingPathComponent("-dirlink"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: outside.appendingPathComponent("x"), withDestinationURL: real)
        let reader = ClaudeProjectsTailReader(root: projects)
        XCTAssertNil(reader.readTail(sessionID: "linked", maxBytes: 1024), "dosya symlink'i izlenmez")
        XCTAssertNil(reader.readTail(sessionID: "real", maxBytes: 1024), "dizin symlink'i izlenmez")
    }

    func testRealReaderIgnoresDirectoriesNamedLikeSession() throws {
        let dir = tmp.appendingPathComponent("-p/sid.jsonl", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertNil(ClaudeProjectsTailReader(root: tmp).readTail(sessionID: "sid", maxBytes: 1024))
    }

    // MARK: Hız sınırı

    func testLookupTrackerBackoffAndCap() {
        var t = ModelLookupTracker()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var now = t0
        XCTAssertTrue(t.shouldAttempt("s", now: now))
        XCTAssertFalse(t.shouldAttempt("s", now: now), "uçuştayken ikinci deneme yok")
        t.finish("s", found: false, now: now)
        XCTAssertFalse(t.shouldAttempt("s", now: now.addingTimeInterval(29)))
        let delays: [TimeInterval] = [30, 60, 120, 240]
        var count = 1
        for d in delays {
            now = now.addingTimeInterval(d)
            XCTAssertTrue(t.shouldAttempt("s", now: now), "deneme \(count + 1)")
            count += 1
            t.finish("s", found: false, now: now)
        }
        XCTAssertEqual(t.attempts(for: "s"), 5)
        for d in [480.0, 960, 1920] {
            now = now.addingTimeInterval(d)
            XCTAssertTrue(t.shouldAttempt("s", now: now))
            t.finish("s", found: false, now: now)
        }
        XCTAssertEqual(t.attempts(for: "s"), ModelLookupTracker.maxAttempts)
        XCTAssertEqual(ModelLookupTracker.maxAttempts, 8)
        XCTAssertFalse(t.shouldAttempt("s", now: now.addingTimeInterval(1_000_000)), "en çok 8 deneme")
    }

    func testLookupTrackerFastIntervalsForPostToolUse() {
        var t = ModelLookupTracker()
        var now = Date(timeIntervalSince1970: 1_000_000)
        for n in 1...3 {
            XCTAssertTrue(t.shouldAttempt("s", now: now, fast: true), "hızlı deneme \(n)")
            t.finish("s", found: false, now: now)
            XCTAssertFalse(t.shouldAttempt("s", now: now.addingTimeInterval(4.9), fast: true))
            now = now.addingTimeInterval(5)
        }
        XCTAssertTrue(t.shouldAttempt("s", now: now, fast: true), "4. deneme")
        t.finish("s", found: false, now: now)
        XCTAssertFalse(t.shouldAttempt("s", now: now.addingTimeInterval(29), fast: true), "4. denemeden sonra 30 sn")
        now = now.addingTimeInterval(30)
        XCTAssertTrue(t.shouldAttempt("s", now: now, fast: true))
        t.finish("s", found: false, now: now)
        XCTAssertFalse(t.shouldAttempt("s", now: now.addingTimeInterval(59), fast: true), "sonra 60 sn")
        XCTAssertTrue(t.shouldAttempt("s", now: now.addingTimeInterval(60), fast: true))
        // Hızlı olmayan olay aynı oturumda 5 sn aralığı kullanmaz.
        var u = ModelLookupTracker()
        let t0 = Date(timeIntervalSince1970: 7)
        XCTAssertTrue(u.shouldAttempt("x", now: t0)); u.finish("x", found: false, now: t0)
        XCTAssertFalse(u.shouldAttempt("x", now: t0.addingTimeInterval(6)))
    }

    func testLookupTrackerForcedAttemptSkipsBackoffOncePerKind() {
        var t = ModelLookupTracker()
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(t.shouldAttempt("s", now: now)); t.finish("s", found: false, now: now)
        XCTAssertFalse(t.shouldAttempt("s", now: now.addingTimeInterval(1)), "olağan deneme geri çekilmede")
        XCTAssertTrue(t.shouldAttempt("s", now: now.addingTimeInterval(1), force: "Stop"))
        t.finish("s", found: false, now: now.addingTimeInterval(1))
        XCTAssertFalse(t.shouldAttempt("s", now: now.addingTimeInterval(2), force: "Stop"), "aynı tür bir kez")
        XCTAssertTrue(t.shouldAttempt("s", now: now.addingTimeInterval(2), force: "SubagentStop"))
        t.finish("s", found: false, now: now.addingTimeInterval(2))
        XCTAssertTrue(t.shouldAttempt("s", now: now.addingTimeInterval(3), force: "SessionEnd"))
        t.finish("s", found: false, now: now.addingTimeInterval(3))
        XCTAssertTrue(t.shouldAttempt("s", now: now.addingTimeInterval(4), force: "final"))
        t.finish("s", found: true, now: now.addingTimeInterval(4))
        XCTAssertFalse(t.shouldAttempt("s", now: now.addingTimeInterval(5), force: "Other"), "başarıda durur")
        XCTAssertEqual(t.attempts(for: "s"), 1, "zorunlu denemeler olağan sayaca girmez")
    }

    func testLookupTrackerForcedAttemptIgnoresCap() {
        var t = ModelLookupTracker()
        var now = Date(timeIntervalSince1970: 0)
        for _ in 0..<ModelLookupTracker.maxAttempts {
            XCTAssertTrue(t.shouldAttempt("s", now: now)); t.finish("s", found: false, now: now)
            now = now.addingTimeInterval(100_000)
        }
        XCTAssertFalse(t.shouldAttempt("s", now: now))
        XCTAssertTrue(t.shouldAttempt("s", now: now, force: "Stop"))
    }

    func testLookupTrackerStopsOnSuccessAndForgets() {
        var t = ModelLookupTracker()
        let now = Date(timeIntervalSince1970: 5)
        XCTAssertTrue(t.shouldAttempt("s", now: now))
        t.finish("s", found: true, now: now)
        XCTAssertFalse(t.shouldAttempt("s", now: now.addingTimeInterval(10_000)))
        t.retain([])
        XCTAssertTrue(t.shouldAttempt("s", now: now))
    }

    // MARK: Reducer + izleyici entegrasyonu

    private struct FakeResolver: SessionModelResolving {
        var models: [String: String]
        func latestModel(sessionID: String) -> String? { models[sessionID] }
    }

    func testStateAdoptsOnlyWhenModelUnknown() {
        var state = AgentState()
        let t = Date(timeIntervalSince1970: 100)
        state.apply(AgentEvent(event: "UserPromptSubmit", sessionID: "a"), now: t)
        state.apply(AgentEvent(event: "SessionStart", sessionID: "b", model: "claude-opus-4-8"), now: t)
        XCTAssertEqual(state.sessionsWithUnknownModel, ["a"])
        XCTAssertTrue(state.adoptTranscriptModel("claude-sonnet-4-6", for: "a"))
        XCTAssertEqual(state.sessions["a"]?.badge, .sonnet)
        XCTAssertFalse(state.adoptTranscriptModel("claude-haiku-4-5", for: "b"), "bilinen model ezilmez")
        XCTAssertFalse(state.adoptTranscriptModel("claude-haiku-4-5", for: "yok"))
        XCTAssertTrue(state.sessionsWithUnknownModel.isEmpty)
    }

    @MainActor
    func testMonitorResolvesUnknownModelInBackground() async throws {
        let monitor = AgentMonitorModel(modelResolver: FakeResolver(models: ["a": "claude-opus-4-8"]))
        monitor.ingest(AgentEvent(event: "UserPromptSubmit", sessionID: "a"))
        monitor.ingest(AgentEvent(event: "UserPromptSubmit", sessionID: "b"))
        for _ in 0..<100 where monitor.state.sessions["a"]?.badge == .unknown { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(monitor.state.sessions["a"]?.badge, .opus)
        XCTAssertEqual(monitor.state.sessions["b"]?.badge, .unknown)
        monitor.reset()
    }

    /// Çağrı sayan sahte çözücü: ilk `failures` çağrıda nil, sonra model.
    private final class CountingResolver: SessionModelResolving, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        let failures: Int
        init(failures: Int) { self.failures = failures }
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
        func latestModel(sessionID: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            calls += 1
            return calls > failures ? "claude-sonnet-4-6" : nil
        }
    }

    @MainActor
    private func waitUntil(_ cond: () -> Bool) async throws {
        for _ in 0..<150 where !cond() { try await Task.sleep(for: .milliseconds(20)) }
    }

    @MainActor
    func testMonitorStopEventForcesLookupDespiteBackoff() async throws {
        let resolver = CountingResolver(failures: 1)
        let monitor = AgentMonitorModel(modelResolver: resolver)
        let t0 = Date()
        monitor.ingest(AgentEvent(event: "UserPromptSubmit", sessionID: "a"), now: t0)
        try await waitUntil { resolver.count >= 1 }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(monitor.state.sessions["a"]?.badge, .unknown)
        monitor.ingest(AgentEvent(event: "PreToolUse", sessionID: "a"), now: t0.addingTimeInterval(1))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(resolver.count, 1, "geri çekilme sürerken olağan olay aramaz")
        monitor.ingest(AgentEvent(event: "Stop", sessionID: "a"), now: t0.addingTimeInterval(2))
        try await waitUntil { monitor.state.sessions["a"]?.badge != .unknown }
        XCTAssertEqual(resolver.count, 2)
        XCTAssertEqual(monitor.state.sessions["a"]?.badge, .sonnet)
        monitor.reset()
    }

    @MainActor
    func testMonitorSessionEndLooksUpEndedSession() async throws {
        let resolver = CountingResolver(failures: 1)
        let monitor = AgentMonitorModel(modelResolver: resolver)
        let t0 = Date()
        monitor.ingest(AgentEvent(event: "UserPromptSubmit", sessionID: "a"), now: t0)
        try await waitUntil { resolver.count >= 1 }
        try await Task.sleep(for: .milliseconds(100))
        monitor.ingest(AgentEvent(event: "SessionEnd", sessionID: "a"), now: t0.addingTimeInterval(1))
        try await waitUntil { monitor.state.sessions["a"]?.badge != .unknown }
        XCTAssertEqual(monitor.state.sessions["a"]?.status, .ended)
        XCTAssertEqual(monitor.state.sessions["a"]?.badge, .sonnet)
        monitor.reset()
    }

    @MainActor
    func testMonitorFinalLookupAfterSessionEnd() async throws {
        let resolver = CountingResolver(failures: 2)
        let monitor = AgentMonitorModel(modelResolver: resolver)
        monitor.ingest(AgentEvent(event: "UserPromptSubmit", sessionID: "a"))
        try await waitUntil { resolver.count >= 1 }
        try await Task.sleep(for: .milliseconds(100))
        monitor.ingest(AgentEvent(event: "SessionEnd", sessionID: "a"))
        try await waitUntil { resolver.count >= 2 }
        XCTAssertEqual(monitor.state.sessions["a"]?.badge, .unknown)
        try await Task.sleep(for: .seconds(AgentMonitorModel.finalLookupDelay + 3))
        XCTAssertEqual(resolver.count, 3, "kapanış sonrası son deneme")
        XCTAssertEqual(monitor.state.sessions["a"]?.badge, .sonnet)
        monitor.reset()
    }

    @MainActor
    func testMonitorWithoutResolverNeverLooksUp() {
        let monitor = AgentMonitorModel()
        monitor.ingest(AgentEvent(event: "UserPromptSubmit", sessionID: "a"))
        XCTAssertEqual(monitor.state.sessions["a"]?.badge, .unknown)
        monitor.reset()
    }
}
