import XCTest
@testable import Adalmon

/// Model bazında kullanım: satır çözümleyicileri, artımlı okuma, yineleme ayıklama, pencere aralıkları ve paylar.
/// Yalnızca geçici dizindeki fixture jsonl dosyaları okunur (gerçek ~/.claude ya da ~/.codex okunmaz).
final class ModelUsageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ModelUsageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Fixture satırları

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func claudeLine(id: String, model: String, at date: Date, input: Int = 2, output: Int = 10, cacheWrite: Int = 0, cacheRead: Int = 0,
                            text: String = "gizli istem metni") -> String {
        #"{"parentUuid":null,"isSidechain":false,"message":{"model":"\#(model)","id":"\#(id)","type":"message","role":"assistant","content":[{"type":"text","text":"\#(text) \"usage\":{\"input_tokens\":999999}"}],"stop_reason":"end_turn","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheWrite),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output),"output_tokens_details":{"thinking_tokens":0},"iterations":[{"input_tokens":777,"output_tokens":777}],"service_tier":"standard"}},"requestId":"req_1","type":"assistant","uuid":"u","timestamp":"\#(iso(date))","cwd":"/x"}"#
    }

    private func claudeUserLine(at date: Date) -> String {
        #"{"parentUuid":null,"message":{"role":"user","content":"merhaba"},"toolUseResult":{"usage":{"input_tokens":5000,"output_tokens":5000}},"type":"user","timestamp":"\#(iso(date))"}"#
    }

    private func codexTurn(_ model: String, at date: Date) -> String {
        #"{"timestamp":"\#(iso(date))","type":"turn_context","payload":{"turn_id":"t","cwd":"/x","model":"\#(model)","collaboration_mode":{"settings":{"model":"yanlis"}}}}"#
    }

    private func codexCount(at date: Date, input: Int, cached: Int, output: Int, total: Int) -> String {
        #"{"timestamp":"\#(iso(date))","ordinal":1,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"total_tokens":\#(total)},"last_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":0,"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(input + output)},"model_context_window":1000},"rate_limits":{"primary":{"used_percent":5}}}}"#
    }

    @discardableResult
    private func write(_ lines: [String], to path: String, append: Bool = false) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        if append, let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url)
        }
        return url
    }

    private func bytes<T>(_ line: String, _ body: (UnsafeRawBufferPointer) -> T) -> T {
        Array(line.utf8).withUnsafeBytes(body)
    }

    // MARK: Çözümleyiciler

    func testClaudeParserReadsModelTokensAndTimeIgnoringEscapedTextAndNestedIterations() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000.5)
        let line = claudeLine(id: "msg_A", model: "claude-opus-5-5", at: date, input: 3, output: 40, cacheWrite: 500, cacheRead: 6000)
        let sample = try XCTUnwrap(bytes(line) { ClaudeTranscriptUsageParser.parse(line: $0) })
        XCTAssertEqual(sample.model, "claude-opus-5-5")
        XCTAssertEqual(sample.tokens, ModelTokens(input: 3, output: 40, cacheWrite: 500, cacheRead: 6000))
        XCTAssertEqual(sample.timestamp, date.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertNotEqual(sample.key, 0)
    }

    func testClaudeParserIgnoresUserSyntheticAndZeroLines() {
        XCTAssertNil(bytes(claudeUserLine(at: .now)) { ClaudeTranscriptUsageParser.parse(line: $0) })
        XCTAssertNil(bytes(claudeLine(id: "m", model: "<synthetic>", at: .now)) { ClaudeTranscriptUsageParser.parse(line: $0) })
        XCTAssertNil(bytes(claudeLine(id: "m", model: "claude-opus-5-5", at: .now, input: 0, output: 0)) { ClaudeTranscriptUsageParser.parse(line: $0) })
        XCTAssertNil(bytes("{\"type\":\"summary\"}") { ClaudeTranscriptUsageParser.parse(line: $0) })
        XCTAssertNil(bytes("{bozuk json \"message\":{\"role\":\"assistant\"") { ClaudeTranscriptUsageParser.parse(line: $0) })
    }

    func testCodexParserReadsModelAndIncludedCachedInput() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_100)
        XCTAssertEqual(bytes(codexTurn("gpt-6.1-sol", at: date)) { CodexRolloutUsageParser.parse(line: $0) }, .model("gpt-6.1-sol"))
        let event = bytes(codexCount(at: date, input: 1000, cached: 400, output: 50, total: 1050)) { CodexRolloutUsageParser.parse(line: $0) }
        guard case let .usage(time, tokens, total)? = event else { return XCTFail("kullanım olayı çözülmedi") }
        XCTAssertEqual(time, date.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(tokens, ModelTokens(input: 600, output: 50, cacheWrite: 0, cacheRead: 400))
        XCTAssertEqual(total, 1050)
        XCTAssertNil(bytes(#"{"timestamp":"2026-01-01T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#) { CodexRolloutUsageParser.parse(line: $0) })
    }

    func testTimestampParserHandlesFractionAndRejectsGarbage() {
        func parse(_ text: String) -> TimeInterval? { Array(text.utf8).withUnsafeBytes { UsageBytes.timestamp(at: 0, in: $0) } }
        XCTAssertEqual(parse("2026-11-11T17:36:19.695Z") ?? 0, 1_794_418_579.695, accuracy: 0.001)
        XCTAssertEqual(parse("1970-01-01T00:00:00Z") ?? -1, 0, accuracy: 0.001)
        XCTAssertNil(parse("2026-13-11T17:36:19Z"))
        XCTAssertNil(parse("bozuk"))
    }

    // MARK: Depo: Claude

    func testStoreDedupesStreamedMessageLinesAcrossAndWithinFiles() throws {
        let now = Date()
        let t = now.addingTimeInterval(-600)
        // Aynı mesaj akışta üç satır: sayılar büyür; ikinci dosyada devam oturumu aynı mesajı yeniden yazar.
        try write([claudeLine(id: "msg_1", model: "claude-opus-5-5", at: t, output: 5),
                   claudeLine(id: "msg_1", model: "claude-opus-5-5", at: t, output: 90),
                   claudeLine(id: "msg_2", model: "claude-sonnet-5-5", at: t, output: 20, cacheRead: 1000),
                   claudeUserLine(at: t)], to: "proj/a.jsonl")
        try write([claudeLine(id: "msg_1", model: "claude-opus-5-5", at: t, output: 90)], to: "proj/sub/b.jsonl")
        let store = ModelUsageStore(claudeRoot: root, codexRoot: root.appending(path: "none"))
        store.refresh(.claude, since: now.addingTimeInterval(-3600), now: now)
        let rows = store.aggregate(.claude, from: now.addingTimeInterval(-3600), to: now)
        XCTAssertEqual(rows.count, 2)
        let opus = try XCTUnwrap(rows.first { $0.model == "claude-opus-5-5" })
        XCTAssertEqual(opus.messages, 1)
        XCTAssertEqual(opus.tokens.output, 90)
        XCTAssertEqual(try XCTUnwrap(rows.first { $0.model == "claude-sonnet-5-5" }).tokens.cacheRead, 1000)
    }

    func testStoreIsIncrementalAndOnlyReadsAppendedBytes() throws {
        let now = Date()
        let t = now.addingTimeInterval(-300)
        let url = try write([claudeLine(id: "msg_1", model: "claude-opus-5-5", at: t)], to: "p/a.jsonl")
        let store = ModelUsageStore(claudeRoot: root, codexRoot: root.appending(path: "none"))
        let first = store.refresh(.claude, since: now.addingTimeInterval(-3600), now: now)
        XCTAssertEqual(first.filesRead, 1)
        XCTAssertEqual(first.newRecords, 1)
        let size = try XCTUnwrap(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertEqual(first.bytesRead, UInt64(size))

        // Değişiklik yok: dosyaya dokunulmaz.
        let idle = store.refresh(.claude, since: now.addingTimeInterval(-3600), now: now)
        XCTAssertEqual(idle.filesRead, 0)
        XCTAssertEqual(idle.bytesRead, 0)

        // Sonuna eklenir: yalnızca yeni baytlar okunur.
        let addition = claudeLine(id: "msg_2", model: "claude-haiku-5-5", at: t)
        try write([addition], to: "p/a.jsonl", append: true)
        let grown = store.refresh(.claude, since: now.addingTimeInterval(-3600), now: now)
        XCTAssertEqual(grown.filesRead, 1)
        XCTAssertEqual(grown.bytesRead, UInt64(addition.utf8.count + 1))
        XCTAssertEqual(grown.newRecords, 1)
        XCTAssertEqual(store.aggregate(.claude, from: now.addingTimeInterval(-3600), to: now).count, 2)
    }

    func testStoreSkipsFilesOlderThanWindowStartAndRecordsOutsideRange() throws {
        let now = Date()
        let oldURL = try write([claudeLine(id: "old", model: "claude-opus-5-5", at: now.addingTimeInterval(-10 * 86_400))], to: "p/old.jsonl")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10 * 86_400)], ofItemAtPath: oldURL.path(percentEncoded: false))
        try write([claudeLine(id: "inside", model: "claude-sonnet-5-5", at: now.addingTimeInterval(-3600)),
                   claudeLine(id: "before", model: "claude-opus-5-5", at: now.addingTimeInterval(-6 * 3600))], to: "p/new.jsonl")
        let store = ModelUsageStore(claudeRoot: root, codexRoot: root.appending(path: "none"))
        let stats = store.refresh(.claude, since: now.addingTimeInterval(-5 * 3600), now: now)
        XCTAssertEqual(stats.filesConsidered, 1, "mtime penceren eskiyse dosya hiç okunmaz")
        let fiveHours = store.aggregate(.claude, from: now.addingTimeInterval(-5 * 3600), to: now)
        XCTAssertEqual(fiveHours.map(\.model), ["claude-sonnet-5-5"])
    }

    func testStoreHandlesLinesLargerThanTheReadChunk() throws {
        let now = Date()
        let big = String(repeating: "x", count: ModelUsageStore.chunkBytes * 2 + 123)
        try write([claudeLine(id: "big", model: "claude-opus-5-5", at: now, text: big), claudeLine(id: "small", model: "claude-sonnet-5-5", at: now)],
                  to: "p/big.jsonl")
        let store = ModelUsageStore(claudeRoot: root, codexRoot: root.appending(path: "none"))
        store.refresh(.claude, since: now.addingTimeInterval(-60), now: now)
        XCTAssertEqual(Set(store.aggregate(.claude, from: now.addingTimeInterval(-60), to: now.addingTimeInterval(60)).map(\.model)),
                       ["claude-opus-5-5", "claude-sonnet-5-5"])
    }

    func testStoreLeavesPartialTrailingLineForNextRead() throws {
        let now = Date()
        let first = claudeLine(id: "a", model: "claude-opus-5-5", at: now)
        let second = claudeLine(id: "b", model: "claude-sonnet-5-5", at: now)
        let half = second.index(second.startIndex, offsetBy: second.count / 2)
        let url = root.appending(path: "p/a.jsonl")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((first + "\n" + second[..<half]).utf8).write(to: url)
        let store = ModelUsageStore(claudeRoot: root, codexRoot: root.appending(path: "none"))
        store.refresh(.claude, since: now.addingTimeInterval(-60), now: now)
        XCTAssertEqual(store.aggregate(.claude, from: now.addingTimeInterval(-60), to: now.addingTimeInterval(60)).count, 1)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((second[half...] + "\n").utf8))
        try handle.close()
        store.refresh(.claude, since: now.addingTimeInterval(-60), now: now)
        XCTAssertEqual(store.aggregate(.claude, from: now.addingTimeInterval(-60), to: now.addingTimeInterval(60)).count, 2)
    }

    // MARK: Depo: Codex

    func testCodexStoreTracksModelPerTurnAndSkipsRepeatedTotals() throws {
        let now = Date()
        let t = now.addingTimeInterval(-120)
        try write([codexTurn("gpt-6.1-sol", at: t),
                   codexCount(at: t, input: 1000, cached: 400, output: 50, total: 1050),
                   codexCount(at: t, input: 1000, cached: 400, output: 50, total: 1050),
                   codexTurn("gpt-6.1-terra", at: t),
                   codexCount(at: t, input: 200, cached: 0, output: 10, total: 1260)], to: "2026/11/11/rollout-x.jsonl")
        try write(["{}"], to: "2026/11/11/not-a-rollout.jsonl")
        let store = ModelUsageStore(claudeRoot: root.appending(path: "none"), codexRoot: root)
        store.refresh(.codex, since: now.addingTimeInterval(-3600), now: now)
        let rows = store.aggregate(.codex, from: now.addingTimeInterval(-3600), to: now)
        let sol = try XCTUnwrap(rows.first { $0.model == "gpt-6.1-sol" })
        XCTAssertEqual(sol.messages, 1)
        XCTAssertEqual(sol.tokens, ModelTokens(input: 600, output: 50, cacheWrite: 0, cacheRead: 400))
        XCTAssertEqual(try XCTUnwrap(rows.first { $0.model == "gpt-6.1-terra" }).tokens.input, 200)
    }

    func testCodexModelCarriesAcrossIncrementalReads() throws {
        let now = Date()
        let t = now.addingTimeInterval(-120)
        try write([codexTurn("gpt-6.1-sol", at: t), codexCount(at: t, input: 100, cached: 0, output: 5, total: 105)], to: "2026/11/11/rollout-y.jsonl")
        let store = ModelUsageStore(claudeRoot: root.appending(path: "none"), codexRoot: root)
        store.refresh(.codex, since: now.addingTimeInterval(-3600), now: now)
        try write([codexCount(at: t, input: 100, cached: 0, output: 5, total: 210)], to: "2026/11/11/rollout-y.jsonl", append: true)
        store.refresh(.codex, since: now.addingTimeInterval(-3600), now: now)
        let rows = store.aggregate(.codex, from: now.addingTimeInterval(-3600), to: now)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].model, "gpt-6.1-sol")
        XCTAssertEqual(rows[0].messages, 2)
    }

    // MARK: Fiyat ağırlığı, paylar, pencere aralıkları

    func testPricingOrdersOpusAboveSonnetAboveHaikuAndNamesAreReadable() {
        func cost(_ model: String) -> Double {
            ModelPricing.cost(ModelTokens(input: 1000, output: 1000, cacheWrite: 1000, cacheRead: 1000), rates: ModelPricing.rates(for: model, source: .claude))
        }
        XCTAssertGreaterThan(cost("claude-opus-5-5"), cost("claude-sonnet-5-5"))
        XCTAssertGreaterThan(cost("claude-sonnet-5-5"), cost("claude-haiku-5-5"))
        XCTAssertGreaterThan(cost("claude-opus-4-1"), cost("claude-opus-5-5"))
        XCTAssertEqual(ModelNaming.display("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(ModelNaming.display("claude-haiku-4-5-20251001"), "Haiku 4.5")
        XCTAssertEqual(ModelNaming.display("claude-3-5-sonnet-20241022"), "Sonnet 3.5")
        XCTAssertEqual(ModelNaming.display("gpt-6.1-sol"), "GPT-6.1 Sol")
        XCTAssertEqual(ModelNaming.display("o3"), "o3")
    }

    func testSharesAreCostWeightedAndSumToUsedPercent() {
        let range = ModelUsageBuilder.Range(kind: .weekly, start: .now, end: .now, usedPercent: 40, isFallback: false)
        // Aynı token sayısı: Opus (5/25) Sonnet'ten (3/15) pahalı → daha büyük pay.
        let tokens = ModelTokens(input: 0, output: 1_000_000)
        let window = ModelUsageBuilder.window(source: .claude, range: range, aggregates: [
            ModelAggregate(model: "claude-sonnet-5-5", tokens: tokens, messages: 10),
            ModelAggregate(model: "claude-opus-5-5", tokens: tokens, messages: 4)])
        XCTAssertEqual(window.rows.map(\.name), ["Opus 5.5", "Sonnet 5.5"])
        XCTAssertEqual(window.rows[0].costShare, 25.0 / 40.0, accuracy: 1e-9)
        XCTAssertEqual(window.rows.compactMap(\.approxPercent).reduce(0, +), 40, accuracy: 1e-9)
        XCTAssertEqual(window.totalMessages, 14)
    }

    func testManyModelsCollapseIntoOtherRowAndPercentIsOptional() {
        let range = ModelUsageBuilder.Range(kind: .fiveHour, start: .now, end: .now, usedPercent: nil, isFallback: true)
        let aggregates = (1...8).map { ModelAggregate(model: "gpt-\($0)", tokens: ModelTokens(output: 1000 * $0), messages: $0) }
        let window = ModelUsageBuilder.window(source: .codex, range: range, aggregates: aggregates)
        XCTAssertEqual(window.rows.count, ModelUsageBuilder.maxRows)
        XCTAssertTrue(window.rows.last?.isOther == true)
        XCTAssertEqual(window.rows.last?.messages, (1...4).reduce(0, +))
        XCTAssertTrue(window.rows.allSatisfy { $0.approxPercent == nil })
        XCTAssertEqual(window.rows.map(\.costShare).reduce(0, +), 1, accuracy: 1e-9)
    }

    func testRangesUseWindowStartOrFallAndSkipMissingWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weeklyOnly = ProviderLimits(source: .claude, fiveHour: nil,
                                        weekly: LimitWindow(usedPercent: 30, resetsAt: now.addingTimeInterval(2 * 86_400)), observedAt: now)
        let ranges = ModelUsageBuilder.ranges(for: weeklyOnly, now: now)
        XCTAssertEqual(ranges.map(\.kind), [.weekly], "gelmeyen 5 saatlik pencere için aralık üretilmez")
        XCTAssertEqual(ranges[0].start, now.addingTimeInterval(2 * 86_400 - 7 * 86_400))
        XCTAssertEqual(ranges[0].usedPercent, 30)
        XCTAssertFalse(ranges[0].isFallback)

        let both = ProviderLimits(source: .codex, fiveHour: LimitWindow(usedPercent: 10, resetsAt: nil),
                                  weekly: LimitWindow(usedPercent: 50, resetsAt: now.addingTimeInterval(-60)), observedAt: now)
        let fallback = ModelUsageBuilder.ranges(for: both, now: now)
        XCTAssertEqual(fallback.map(\.kind), [.fiveHour, .weekly])
        XCTAssertTrue(fallback.allSatisfy { $0.isFallback && $0.usedPercent == nil })
        XCTAssertEqual(fallback[0].start, now.addingTimeInterval(-5 * 3600))
        XCTAssertEqual(fallback[1].start, now.addingTimeInterval(-7 * 86_400))
    }

    func testFormatting() {
        XCTAssertEqual(ModelUsageFormat.tokens(950), "950")
        XCTAssertEqual(ModelUsageFormat.tokens(12_300), "12K")
        XCTAssertEqual(ModelUsageFormat.tokens(1_500), "1,5K")
        XCTAssertEqual(ModelUsageFormat.tokens(4_500_000), "4,5Mn")
        XCTAssertEqual(ModelUsageFormat.tokens(2_000_000_000), "2Mr")
        XCTAssertEqual(ModelUsageFormat.approxPercent(23.4), "≈ %23")
        XCTAssertEqual(ModelUsageFormat.approxPercent(0.43), "≈ %0,4")
        XCTAssertNil(ModelUsageFormat.approxPercent(nil))
    }

    // MARK: Model entegrasyonu

    @MainActor
    func testModelComputesUsageForProvidersThatHaveData() async throws {
        let now = Date()
        try write([claudeLine(id: "m1", model: "claude-opus-5-5", at: now.addingTimeInterval(-3600), output: 1000)], to: "claude/p/a.jsonl")
        let suite = "ModelUsageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModelUsageStore(claudeRoot: root.appending(path: "claude"), codexRoot: root.appending(path: "codex"))
        let model = SubscriptionLimitsModel(defaults: defaults, usageStore: store, live: false)
        await model.refreshModelUsageNow(force: true, now: now)
        XCTAssertTrue(model.modelUsage.isEmpty, "limit verisi olmayan sağlayıcı için hesaplanmaz")

        // Yalnızca haftalık: 5 saatlik pencere için model kullanımı da üretilmez.
        model.ingestClaude(ProviderLimits(source: .claude, fiveHour: nil,
                                          weekly: LimitWindow(usedPercent: 50, resetsAt: now.addingTimeInterval(86_400)), observedAt: now), now: now)
        await model.refreshModelUsageNow(force: true, now: now)
        let usage = try XCTUnwrap(model.modelUsage[.claude])
        XCTAssertEqual(usage.windows.map(\.kind), [.weekly])
        XCTAssertEqual(usage.windows[0].rows.first?.name, "Opus 5.5")
        XCTAssertEqual(try XCTUnwrap(usage.windows[0].rows.first?.approxPercent), 50, accuracy: 1e-9)
        XCTAssertEqual(model.snapshot(agentsEnabled: true, now: now).modelUsage[.claude], usage)
    }

    @MainActor
    func testModelThrottlesRepeatedRefreshesWithinAMinute() async throws {
        let now = Date()
        let suite = "ModelUsageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModelUsageStore(claudeRoot: root.appending(path: "claude"), codexRoot: root.appending(path: "codex"))
        let model = SubscriptionLimitsModel(defaults: defaults, usageStore: store, live: false)
        model.ingestClaude(ProviderLimits(source: .claude, fiveHour: LimitWindow(usedPercent: 10, resetsAt: now.addingTimeInterval(3600)),
                                          weekly: nil, observedAt: now), now: now)
        try write([claudeLine(id: "m1", model: "claude-opus-5-5", at: now.addingTimeInterval(-60))], to: "claude/p/a.jsonl")
        await model.refreshModelUsageNow(force: false, now: now)
        XCTAssertEqual(model.modelUsage[.claude]?.window(.fiveHour)?.totalMessages, 1)
        try write([claudeLine(id: "m2", model: "claude-opus-5-5", at: now.addingTimeInterval(-30))], to: "claude/p/a.jsonl", append: true)
        await model.refreshModelUsageNow(force: false, now: now.addingTimeInterval(20))
        XCTAssertEqual(model.modelUsage[.claude]?.window(.fiveHour)?.totalMessages, 1, "dakikadan sık taranmaz")
        await model.refreshModelUsageNow(force: false, now: now.addingTimeInterval(61))
        XCTAssertEqual(model.modelUsage[.claude]?.window(.fiveHour)?.totalMessages, 2)
    }
}
