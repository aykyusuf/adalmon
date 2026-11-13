import XCTest
@testable import Adalmon

/// Codex canlı limitleri: yanıt ayrıştırma (fixture), ikili bulma, süreç istemcisi (SAHTE ikili; gerçek codex başlatılmaz),
/// izinli metot listesi, kaynak önceliği ve gizlilik (accountId / hak kimliği hiçbir modele girmez).
final class CodexLiveLimitsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_794_500_000)
    let accountID = "acct-SECRET-1234"
    let creditID = "credit-SECRET-5678"

    private var fixtureLine: String {
        """
        {"id":2,"result":{"ordinaryUsageAllowed":true,"rateLimits":{"limitId":"codex","primary":{"usedPercent":6,"windowDurationMins":300,"resetsAt":1794502968},"secondary":{"usedPercent":17,"windowDurationMins":10080,"resetsAt":1795071631},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"plus","rateLimitReachedType":null,"spendControlReached":false},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":6,"windowDurationMins":300,"resetsAt":1794502968},"secondary":{"usedPercent":17,"windowDurationMins":10080,"resetsAt":1795071631},"planType":"plus","rateLimitReachedType":null}},"rateLimitResetCredits":{"availableCount":1,"credits":[{"id":"\(creditID)","title":"Full reset (Weekly + 5 hr)","description":"Resets both windows","resetType":"codexRateLimits","status":"available","grantedAt":1794400000,"expiresAt":1795500000}]},"accountId":"\(accountID)"}}
        """
    }

    func parse(_ text: String) -> ProviderLimits? {
        CodexAppServerParser.limits(fromResponse: Data(text.utf8), now: now)
    }

    // MARK: Ayrıştırma

    func testParsesLiveResponse() throws {
        let limits = try XCTUnwrap(parse(fixtureLine))
        XCTAssertEqual(limits.source, .codex)
        XCTAssertEqual(limits.fiveHour?.usedPercent, 6)
        XCTAssertEqual(limits.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_794_502_968))
        XCTAssertEqual(limits.weekly?.usedPercent, 17)
        XCTAssertEqual(limits.weekly?.resetsAt, Date(timeIntervalSince1970: 1_795_071_631))
        XCTAssertEqual(limits.planType, "plus")
        XCTAssertNil(limits.creditsBalance, "hasCredits == false → bakiye gösterilmez")
        XCTAssertEqual(limits.isLive, true)
        XCTAssertEqual(limits.limitReached, false)
        XCTAssertEqual(limits.observedAt, now)
        XCTAssertEqual(limits.resetCreditCount, 1)
        let credit = try XCTUnwrap(limits.resetCredits?.first)
        XCTAssertEqual(credit.title, "Full reset (Weekly + 5 hr)")
        XCTAssertEqual(credit.detail, "Resets both windows")
        XCTAssertEqual(credit.resetType, "codexRateLimits")
        XCTAssertEqual(credit.status, "available")
        XCTAssertEqual(credit.grantedAt, Date(timeIntervalSince1970: 1_794_400_000))
        XCTAssertEqual(credit.expiresAt, Date(timeIntervalSince1970: 1_795_500_000))
        XCTAssertEqual(credit.typeText, "Haftalık + 5 saatlik tam sıfırlama")
        XCTAssertEqual(credit.statusText, "Kullanılabilir")
        XCTAssertEqual(credit.remainingText(now: now), "11 gün kaldı")
    }

    func testReachedTypeAndCreditsBalance() throws {
        let text = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":1794502968},"credits":{"hasCredits":true,"unlimited":false,"balance":"12.5"},"rateLimitReachedType":"rate_limit_reached"}}}"#
        let limits = try XCTUnwrap(parse(text))
        XCTAssertEqual(limits.limitReached, true)
        XCTAssertEqual(limits.creditsBalance, 12.5)
        XCTAssertNil(limits.weekly)
        XCTAssertNil(limits.resetCredits)
    }

    func testRejectsErrorsAndEmptyResults() {
        XCTAssertNil(parse(#"{"id":2,"error":{"code":-32600,"message":"nope"}}"#))
        XCTAssertNil(parse(#"{"id":2,"result":{"rateLimits":{"primary":null,"secondary":null}}}"#))
        XCTAssertNil(parse("not json"))
        XCTAssertNil(parse(#"{"id":2,"result":{}}"#))
    }

    func testResponseLineSkipsNotificationsAndServerRequests() throws {
        let buffer = """
        {"method":"account/rateLimits/updated","params":{"x":1}}
        {"id":2,"method":"item/requestApproval","params":{}}
        {"id":1,"result":{}}
        \(fixtureLine)
        """
        let line = try XCTUnwrap(CodexAppServerParser.responseLine(in: Data(buffer.utf8), requestID: 2))
        XCTAssertNotNil(CodexAppServerParser.limits(fromResponse: line, now: now))
        XCTAssertNil(CodexAppServerParser.responseLine(in: Data("{\"id\":1,\"result\":{}}\n".utf8), requestID: 2))
    }

    // MARK: Gizlilik

    func testAccountAndCreditIdentifiersNeverEnterModel() throws {
        let limits = try XCTUnwrap(parse(fixtureLine))
        let json = String(decoding: try JSONEncoder().encode(limits), as: UTF8.self)
        XCTAssertFalse(json.contains(accountID))
        XCTAssertFalse(json.contains(creditID))
        XCTAssertFalse(json.contains("accountId"))
        let dump = String(describing: limits)
        XCTAssertFalse(dump.contains(accountID))
        XCTAssertFalse(dump.contains(creditID))
        // Sunum modeli de aynı bilgiyi taşır, kimlik taşımaz.
        let display = LimitsPresentation.sections(providers: [limits], claudeConnected: false, agentsEnabled: false, codexEnabled: true,
                                                  thresholds: LimitAlertThresholds(), now: now, forecast: { _, _ in nil })[1]
        XCTAssertFalse(String(describing: display).contains(accountID))
        XCTAssertFalse(String(describing: display).contains(creditID))
    }

    // MARK: İzinli metotlar ve kaynak taraması

    func testOnlyAllowedMethodsCanBeEncoded() throws {
        XCTAssertEqual(CodexRPC.allowedMethods, ["initialize", "initialized", "account/rateLimits/read"])
        XCTAssertEqual(try CodexRPC.line(method: "account/rateLimits/read", id: 2, paramsJSON: "null"),
                       #"{"id":2,"method":"account/rateLimits/read","params":null}"#)
        XCTAssertEqual(try CodexRPC.line(method: "initialized", id: nil, paramsJSON: nil), #"{"method":"initialized"}"#)
        for method in ["account/logout", "thread/start", "", "account/rateLimits/read2"] {
            XCTAssertThrowsError(try CodexRPC.line(method: method, id: 3, paramsJSON: nil)) { error in
                XCTAssertEqual(error as? CodexRPC.DisallowedMethod, .init(method: method))
            }
        }
    }

    func testSourcesNeverMentionResetConsumption() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/App", directoryHint: .isDirectory)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            scanned += 1
            XCTAssertFalse(text.contains("rateLimitResetCredit/"), "\(url.lastPathComponent): sıfırlama hakkı RPC'si geçmemeli")
            let path = url.path
            if path.contains("/Agents/Limits/") || path.contains("/UI/Limits/") {
                // Metot/çağrı adı olarak "consume…(" ve "…/consume" geçmemeli ("consumed" gibi değişken adları serbest).
                XCTAssertNil(text.range(of: #"(?i)consume\w*\s*\("#, options: .regularExpression), "\(url.lastPathComponent): consume metodu geçmemeli")
                XCTAssertFalse(text.lowercased().contains("/consume"), "\(url.lastPathComponent): '/consume' geçmemeli")
                XCTAssertFalse(text.lowercased().contains("redeem("), "\(url.lastPathComponent): hak kullanma metodu olmamalı")
            }
        }
        XCTAssertGreaterThan(scanned, 100, "kaynak ağacı bulunamadı")
    }

    // MARK: İkili bulma

    private func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "adalmon-codexlive-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    @discardableResult
    private func script(_ body: String, at url: URL) throws -> URL {
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testLocatorFallsBackSilentlyWhenBinaryMissing() throws {
        let empty = try temp()
        let shellCalls = Counter()
        let locator = CodexBinaryLocator(directories: { [empty] }, shellResolver: { shellCalls.bump(); return nil })
        XCTAssertNil(locator.locate(now: now))
        XCTAssertNil(locator.locate(now: now.addingTimeInterval(60)), "kaçırma kısa süre hatırlanır")
        XCTAssertEqual(shellCalls.value, 1, "login shell tekrar tekrar çalıştırılmaz")
        XCTAssertNil(locator.locate(now: now.addingTimeInterval(CodexBinaryLocator.missMemory + 1)))
        XCTAssertEqual(shellCalls.value, 2)
        // İkili yoksa canlı okuma nil döner (çağıran rollout'a düşer).
        XCTAssertNil(CodexLiveLimits(locator: locator).fetch(now: now.addingTimeInterval(1)))
    }

    func testLocatorFindsDirectoryThenCaches() throws {
        let dir = try temp()
        let bin = try script("exit 0", at: dir.appending(path: "codex"))
        let locator = CodexBinaryLocator(directories: { [dir] }, shellResolver: { nil })
        XCTAssertEqual(locator.locate()?.path, bin.path)
        try FileManager.default.removeItem(at: bin)
        XCTAssertNil(locator.locate(), "önbellekteki yol silindiyse yeniden aranır")
    }

    func testLocatorUsesLoginShellResultOnce() throws {
        let dir = try temp()
        let bin = try script("exit 0", at: dir.appending(path: "codex-elsewhere"))
        let calls = Counter()
        let locator = CodexBinaryLocator(directories: { [] }, shellResolver: { calls.bump(); return bin })
        XCTAssertEqual(locator.locate()?.path, bin.path)
        XCTAssertEqual(locator.locate()?.path, bin.path)
        XCTAssertEqual(calls.value, 1)
    }

    // MARK: Süreç istemcisi (sahte ikili)

    func testClientReadsResponseFromFakeBinaryAndSendsOnlyAllowedMethods() throws {
        let dir = try temp()
        let log = dir.appending(path: "received.log")
        let fixture = dir.appending(path: "response.json")
        try Data(fixtureLine.utf8).write(to: fixture)
        let bin = try script("""
        while IFS= read -r line; do
          printf '%s\\n' "$line" >> '\(log.path)'
          case "$line" in *account/rateLimits/read*) printf '{"method":"x/noise"}\\n'; cat '\(fixture.path)'; printf '\\n';; esac
        done
        """, at: dir.appending(path: "codex"))
        let started = Date()
        let limits = CodexLiveLimits(timeout: 5, executableOverride: bin).fetch(now: now)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4, "yanıt gelince süreç hemen sonlandırılır")
        XCTAssertEqual(limits?.fiveHour?.usedPercent, 6)
        XCTAssertEqual(limits?.isLive, true)
        let received = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        let methods = try received.map { line -> String in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            return try XCTUnwrap(object["method"] as? String)
        }
        XCTAssertEqual(methods, ["initialize", "initialized", "account/rateLimits/read"])
        XCTAssertTrue(received[0].contains(#""name":"adalmon""#))
    }

    func testClientTimesOutAndKillsStuckProcess() throws {
        let dir = try temp()
        let pidFile = dir.appending(path: "pid")
        let bin = try script("echo $$ > '\(pidFile.path)'\nexec sleep 60", at: dir.appending(path: "codex"))
        let started = Date()
        XCTAssertNil(CodexLiveLimits(timeout: 1, executableOverride: bin).fetch(now: now))
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(elapsed, 0.9)
        XCTAssertLessThan(elapsed, 6)
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1, "süreç sonlandırılmış ve toplanmış olmalı (zombi yok)")
    }

    func testClientHandlesProcessThatExitsEarly() throws {
        let dir = try temp()
        let bin = try script("exit 3", at: dir.appending(path: "codex"))
        XCTAssertNil(CodexLiveLimits(timeout: 5, executableOverride: bin).fetch(now: now))
    }

    // MARK: Kaynak önceliği

    private func limits(five: Double, reset: Double, observed: TimeInterval, live: Bool) -> ProviderLimits {
        var result = ProviderLimits(source: .codex, fiveHour: LimitWindow(usedPercent: five, resetsAt: now.addingTimeInterval(reset)),
                                    observedAt: now.addingTimeInterval(observed))
        if live { result.isLive = true }
        return result
    }

    func testLiveBeatsStaleRolloutWithDifferentReset() throws {
        let rollout = limits(five: 100, reset: -7200, observed: -7 * 3600, live: false)
        let live = limits(five: 6, reset: 3 * 3600, observed: 0, live: true)
        XCTAssertEqual(LimitMerge.codexUpdate(current: rollout, incoming: live)?.fiveHour?.usedPercent, 6)
    }

    func testLiveBeatsRolloutEvenWithSameResetAndLowerValue() throws {
        let rollout = limits(five: 100, reset: 3600, observed: -600, live: false)
        let live = limits(five: 6, reset: 3600, observed: 0, live: true)
        XCTAssertEqual(LimitMerge.codexUpdate(current: rollout, incoming: live)?.fiveHour?.usedPercent, 6)
        // Pasif kaynaklar arasında: aynı/eski olay düşüremez; kesin olarak daha yeni olayın düşüşü (limit sıfırlama) kabul edilir.
        let sameEventLower = limits(five: 50, reset: 3600, observed: -600, live: false)
        XCTAssertNil(LimitMerge.codexUpdate(current: rollout, incoming: sameEventLower))
        let newerLower = limits(five: 50, reset: 3600, observed: 0, live: false)
        XCTAssertEqual(LimitMerge.codexUpdate(current: rollout, incoming: newerLower)?.fiveHour?.usedPercent, 50)
    }

    func testOlderRolloutNeverRewindsLiveValue() throws {
        let live = limits(five: 6, reset: 3600, observed: 0, live: true)
        let oldRollout = limits(five: 100, reset: 3600, observed: -3600, live: false)
        XCTAssertNil(LimitMerge.codexUpdate(current: live, incoming: oldRollout))
        let newerRollout = limits(five: 9, reset: 3600, observed: 120, live: false)
        let merged = try XCTUnwrap(LimitMerge.codexUpdate(current: live, incoming: newerRollout))
        XCTAssertEqual(merged.fiveHour?.usedPercent, 9)
        XCTAssertNil(merged.isLive, "rollout'tan gelen değer canlı rozeti taşımaz")
    }

    func testRolloutKeepsResetCreditsFromLive() throws {
        var live = limits(five: 6, reset: 3600, observed: 0, live: true)
        live.resetCreditCount = 1
        live.resetCredits = [LimitResetCredit(title: "t", detail: nil, resetType: nil, status: "available", grantedAt: nil, expiresAt: nil)]
        let newer = limits(five: 9, reset: 3600, observed: 120, live: false)
        XCTAssertEqual(LimitMerge.codexUpdate(current: live, incoming: newer)?.resetCreditCount, 1)
    }

    @MainActor
    func testModelPrefersLiveOverStaleRollout() throws {
        let dir = try temp()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "adalmon.codexlive.\(UUID().uuidString)"))
        let binder = ClaudeStatusLineBinder(settingsURL: dir.appending(path: "claude/settings.json"),
                                            supportDirectory: dir.appending(path: "support", directoryHint: .isDirectory),
                                            configURL: dir.appending(path: "config.json"))
        let model = SubscriptionLimitsModel(defaults: defaults, binder: binder, codexReader: CodexRolloutReader(root: dir), live: false)
        model.thresholds.notificationsEnabled = false
        let at = Date.now
        func window(_ used: Double, _ reset: TimeInterval) -> LimitWindow { LimitWindow(usedPercent: used, resetsAt: at.addingTimeInterval(reset)) }
        model.ingestCodex(ProviderLimits(source: .codex, fiveHour: window(100, 600), observedAt: at.addingTimeInterval(-3 * 3600)), now: at)
        XCTAssertEqual(model.codex?.fiveHour?.usedPercent, 100)
        var live = ProviderLimits(source: .codex, fiveHour: window(6, 3 * 3600), observedAt: at)
        live.isLive = true
        model.ingestCodex(live, now: at)
        XCTAssertEqual(model.codex?.fiveHour?.usedPercent, 6)
        let snapshot = model.snapshot(agentsEnabled: false, now: at)
        XCTAssertEqual(snapshot.sections[1].display?.freshnessText(now: at), "Canlı · şimdi")
    }

    // MARK: Sunum

    func testPresentationShowsLiveBadgeChipAndReachedState() throws {
        var limits = limits(five: 6, reset: 3600, observed: 0, live: true)
        limits.resetCreditCount = 1
        limits.limitReached = true
        let display = try XCTUnwrap(LimitsPresentation.sections(providers: [limits], claudeConnected: false, agentsEnabled: false,
                                                                 codexEnabled: true, thresholds: LimitAlertThresholds(), now: now,
                                                                 forecast: { _, _ in nil })[1].display)
        XCTAssertEqual(display.freshnessText(now: now), "Canlı · şimdi")
        XCTAssertEqual(display.resetCreditsChipText, "1 ücretsiz sıfırlama hakkı")
        let window = try XCTUnwrap(display.window(.fiveHour))
        XCTAssertTrue(window.isFull)
        XCTAssertEqual(window.statusText, "Limit doldu")
        XCTAssertEqual(window.tone, .critical)
        // Bayat veri "Canlı" rozeti taşımaz.
        let stale = try XCTUnwrap(LimitsPresentation.sections(providers: [limits], claudeConnected: false, agentsEnabled: false,
                                                                codexEnabled: true, thresholds: LimitAlertThresholds(),
                                                                now: now.addingTimeInterval(3600), forecast: { _, _ in nil })[1].display)
        XCTAssertTrue(stale.freshnessText(now: now.addingTimeInterval(3600)).hasPrefix("Son veri"))
    }

    func testPresentationWithoutLiveData() throws {
        let rollout = limits(five: 6, reset: 3600, observed: 0, live: false)
        let display = try XCTUnwrap(LimitsPresentation.sections(providers: [rollout], claudeConnected: false, agentsEnabled: false,
                                                                 codexEnabled: true, thresholds: LimitAlertThresholds(), now: now,
                                                                 forecast: { _, _ in nil })[1].display)
        XCTAssertEqual(display.freshnessText(now: now), "Güncel · şimdi")
        XCTAssertNil(display.resetCreditsChipText)
        XCTAssertFalse(try XCTUnwrap(display.window(.fiveHour)).isFull)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
