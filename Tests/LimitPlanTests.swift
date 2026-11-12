import XCTest
@testable import Adalmon

/// Plan bilgisi (Limitler sayfası): eşleme, dosya okuyucu, Codex `plan_type`, model entegrasyonu. Gerçek ~/.claude.json
/// ya da ~/.codex okunmaz; her test geçici dizinde çalışır.
@MainActor
final class LimitPlanTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appending(path: "adalmon-plan-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temp)
    }

    private func account(_ type: String?, tier: String? = nil, display: String? = nil, billing: String? = nil, extra: Bool? = nil) -> ClaudeAccountPlan {
        ClaudeAccountPlan(planDisplayName: display, organizationType: type, rateLimitTier: tier, billingType: billing, hasExtraUsageEnabled: extra)
    }

    // MARK: Eşleme

    func testClaudeMaxTiers() throws {
        let max20 = try XCTUnwrap(LimitPlanMapper.claude(account("claude_max", tier: "default_claude_max_20x", display: "Ultra",
                                                                 billing: "stripe_subscription", extra: false)))
        XCTAssertEqual(max20.title, "Claude Max 20x")
        XCTAssertEqual(max20.subtitle, "Ultra")
        XCTAssertEqual(max20.billing, "Stripe aboneliği")
        XCTAssertEqual(max20.extraUsage, false)
        XCTAssertEqual(LimitsPresentation.planDetail(max20), "Stripe aboneliği · Ek kullanım kapalı")
        XCTAssertEqual(LimitPlanMapper.claude(account("claude_max", tier: "default_claude_max_5x"))?.title, "Claude Max 5x")
        XCTAssertEqual(LimitPlanMapper.claude(account("claude_max"))?.title, "Claude Max", "katman yoksa çarpan yok")
    }

    func testClaudeOtherOrganizationTypes() {
        XCTAssertEqual(LimitPlanMapper.claude(account("claude_pro", tier: "default_claude_ai"))?.title, "Claude Pro")
        XCTAssertEqual(LimitPlanMapper.claude(account("claude_team"))?.title, "Claude Team")
        XCTAssertEqual(LimitPlanMapper.claude(account("claude_enterprise"))?.title, "Claude Enterprise")
        XCTAssertEqual(LimitPlanMapper.claude(account("claude_free"))?.title, "Claude Free")
    }

    func testClaudeDisplayNameNotRepeated() throws {
        let plan = try XCTUnwrap(LimitPlanMapper.claude(account("claude_max", tier: "default_claude_max_20x", display: "Max")))
        XCTAssertNil(plan.subtitle, "aynı ad iki kez gösterilmez")
    }

    func testClaudeUnknownValues() throws {
        // Bilinmeyen tür: yalnızca planDisplayName kullanılır.
        XCTAssertEqual(LimitPlanMapper.claude(account("claude_galaxy", tier: "x", display: "Galaxy"))?.title, "Claude Galaxy")
        // Bilinmeyen tür ve ad yok: gösterilecek plan yok.
        XCTAssertNil(LimitPlanMapper.claude(account("claude_galaxy")))
        XCTAssertNil(LimitPlanMapper.claude(account(nil)))
        // Bilinmeyen faturalama gösterilmez; garip çarpan yok sayılır.
        let plan = try XCTUnwrap(LimitPlanMapper.claude(account("claude_max", tier: "default_claude_max_9999x", billing: "bilinmeyen")))
        XCTAssertEqual(plan.title, "Claude Max")
        XCTAssertNil(plan.billing)
        // Beklenmedik (uzun / özel karakterli) plan adı ekrana taşınmaz.
        XCTAssertNil(LimitPlanMapper.claude(account("claude_galaxy", display: "<script>alert(1)</script>")))
    }

    func testCodexPlanTypes() {
        XCTAssertEqual(LimitPlanMapper.codex(planType: "plus")?.title, "ChatGPT Plus")
        XCTAssertEqual(LimitPlanMapper.codex(planType: "Pro")?.title, "ChatGPT Pro")
        XCTAssertEqual(LimitPlanMapper.codex(planType: "team")?.title, "ChatGPT Team")
        XCTAssertEqual(LimitPlanMapper.codex(planType: "free")?.title, "ChatGPT Free")
        XCTAssertEqual(LimitPlanMapper.codex(planType: "self_serve_business")?.title, "ChatGPT Self serve business", "bilinmeyen değer okunaklı yapılır")
        XCTAssertNil(LimitPlanMapper.codex(planType: nil))
        XCTAssertNil(LimitPlanMapper.codex(planType: "  "))
        XCTAssertNil(LimitPlanMapper.codex(planType: "a/b;c"), "uygunsuz karakter")
    }

    // MARK: Dosya okuyucu

    private func write(_ text: String, name: String = "claude.json") throws -> URL {
        let url = temp.appending(path: name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testReaderReadsOnlyPlanFields() throws {
        let url = try write("""
        {"numStartups": 3, "projects": {"/x": {"history": ["gizli"]}},
         "oauthAccount": {"accountUuid": "u-1", "emailAddress": "kisi@example.com", "organizationUuid": "o-1", "displayName": "Kisi",
                          "organizationName": "Sirket", "organizationType": "claude_max", "organizationRateLimitTier": "default_claude_max_20x",
                          "billingType": "stripe_subscription", "hasExtraUsageEnabled": false, "planDisplayName": "Ultra"}}
        """)
        let plan = try XCTUnwrap(ClaudePlanReader(url: url).read())
        XCTAssertEqual(plan, account("claude_max", tier: "default_claude_max_20x", display: "Ultra", billing: "stripe_subscription", extra: false))
        let dump = String(describing: plan)
        for secret in ["kisi@example.com", "u-1", "o-1", "Sirket", "Kisi"] { XCTAssertFalse(dump.contains(secret), secret) }
    }

    func testReaderMissingAndBrokenFiles() throws {
        XCTAssertNil(ClaudePlanReader(url: temp.appending(path: "yok.json")).read(), "eksik dosya")
        XCTAssertNil(ClaudePlanReader(url: temp.appending(path: "yok.json")).stamp())
        XCTAssertNil(ClaudePlanReader(url: try write("{bozuk", name: "bozuk.json")).read(), "bozuk JSON")
        XCTAssertNil(ClaudePlanReader(url: try write(#"{"numStartups": 1}"#, name: "bos.json")).read(), "oauthAccount yok")
        XCTAssertNil(ClaudePlanReader(url: try write(#"{"oauthAccount": {"emailAddress": "a@b.c"}}"#, name: "yalniz.json")).read(),
                     "plan alanı yoksa kimlik alanları okunmaz, sonuç boş")
        XCTAssertNil(ClaudePlanReader(url: try write(#"{"oauthAccount": "metin"}"#, name: "tur.json")).read(), "beklenmedik tür")
        let partial = try XCTUnwrap(ClaudePlanReader(url: try write(#"{"oauthAccount": {"organizationType": 5, "planDisplayName": "Pro"}}"#, name: "kismi.json")).read())
        XCTAssertEqual(partial.planDisplayName, "Pro", "bozuk alan yalnızca kendini düşürür")
        XCTAssertNil(partial.organizationType)
    }

    func testReaderStampChangesWithFile() throws {
        let url = try write(#"{"oauthAccount": {"organizationType": "claude_pro"}}"#)
        let reader = ClaudePlanReader(url: url)
        let first = try XCTUnwrap(reader.stamp())
        try Data(#"{"oauthAccount": {"organizationType": "claude_max", "planDisplayName": "Ultra"}}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: first.modified.addingTimeInterval(5)], ofItemAtPath: url.path)
        XCTAssertNotEqual(reader.stamp(), first)
    }

    // MARK: Codex olayı

    func testCodexParserReadsPlanType() throws {
        func line(_ extra: String) -> Data {
            Data(("""
            {"timestamp":"2026-11-12T10:00:00.000Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":41.0,"window_minutes":300,"resets_at":1794484831},"secondary":{"used_percent":6.0,"window_minutes":10080,"resets_at":1795071631}\(extra)}}}
            """ + "\n").utf8)
        }
        let plus = try XCTUnwrap(CodexRolloutParser.latest(tail: line(#","plan_type":"plus""#), truncated: false, fallbackDate: .now))
        XCTAssertEqual(plus.planType, "plus")
        let none = try XCTUnwrap(CodexRolloutParser.latest(tail: line(""), truncated: false, fallbackDate: .now))
        XCTAssertNil(none.planType)
        let odd = try XCTUnwrap(CodexRolloutParser.latest(tail: line(#","plan_type":42"#), truncated: false, fallbackDate: .now))
        XCTAssertNil(odd.planType, "plan türü bozuksa limit okumasını bozmaz")
        XCTAssertEqual(odd.fiveHour?.usedPercent, 41)
        let junk = try XCTUnwrap(CodexRolloutParser.latest(tail: line(#","plan_type":"a/b""#), truncated: false, fallbackDate: .now))
        XCTAssertNil(junk.planType)
    }

    func testPersistedClaudeLimitsWithoutPlanTypeStillDecode() throws {
        let legacy = #"{"source":"claude","observedAt":780000000,"fiveHour":{"usedPercent":10,"resetsAt":780001000}}"#
        let decoded = try JSONDecoder().decode(ProviderLimits.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.source, .claude)
        XCTAssertNil(decoded.planType)
    }

    // MARK: Model

    private func makeModel(planURL: URL, codexRoot: URL? = nil) throws -> (SubscriptionLimitsModel, UserDefaults, String) {
        let suite = "adalmon.limits.plan.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let binder = ClaudeStatusLineBinder(settingsURL: temp.appending(path: "claude/settings.json"),
                                            supportDirectory: temp.appending(path: "support", directoryHint: .isDirectory),
                                            configURL: temp.appending(path: "config.json"))
        let model = SubscriptionLimitsModel(defaults: defaults, binder: binder, codexReader: CodexRolloutReader(root: codexRoot ?? temp),
                                            planReader: ClaudePlanReader(url: planURL), live: false)
        return (model, defaults, suite)
    }

    func testModelReadsPlanOnceAndOnlyWhenFileChanges() async throws {
        let url = try write(#"{"oauthAccount": {"organizationType": "claude_max", "organizationRateLimitTier": "default_claude_max_5x"}}"#)
        let fixed = Date(timeIntervalSince1970: 1_700_000_000) // tam saniye: dosya sistemi hassasiyeti karşılaştırmayı bozmasın
        try FileManager.default.setAttributes([.modificationDate: fixed], ofItemAtPath: url.path)
        let (model, defaults, suite) = try makeModel(planURL: url)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(model.claudePlan, "görünür olmadan okunmaz")
        model.refreshPlan()
        for _ in 0..<100 where model.claudePlan == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.plans[.claude]?.title, "Claude Max 5x")
        // Dosya değişmeden yeniden istek: yeniden okunmaz (aynı boyut + aynı zaman damgasıyla içeriği değişen dosya görülmez).
        let stamp = try XCTUnwrap(ClaudePlanReader(url: url).stamp())
        try Data(#"{"oauthAccount": {"organizationType": "claude_pro", "organizationRateLimitTier": "default_claude_max_5x"}}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: fixed], ofItemAtPath: url.path)
        XCTAssertEqual(ClaudePlanReader(url: url).stamp(), stamp, "test kurulumu: aynı boyut ve zaman damgası")
        model.refreshPlan()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.plans[.claude]?.title, "Claude Max 5x", "damga aynıyken dosya okunmaz")
        // Değişen dosya okunur.
        try Data(#"{"oauthAccount": {"organizationType": "claude_pro", "planDisplayName": "Pro"}, "x": "uzatma"}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: stamp.modified.addingTimeInterval(30)], ofItemAtPath: url.path)
        model.refreshPlan()
        for _ in 0..<100 where model.plans[.claude]?.title != "Claude Pro" { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.plans[.claude]?.title, "Claude Pro")
    }

    func testModelWithMissingPlanFileHasNoPlan() async throws {
        let (model, defaults, suite) = try makeModel(planURL: temp.appending(path: "yok.json"))
        defer { defaults.removePersistentDomain(forName: suite) }
        model.refreshPlan()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(model.claudePlan)
        XCTAssertTrue(model.plans.isEmpty)
        XCTAssertTrue(model.snapshot(agentsEnabled: true, now: .now).plans.isEmpty)
    }

    func testSnapshotCarriesClaudePlan() async throws {
        let url = try write(#"{"oauthAccount": {"organizationType": "claude_max", "organizationRateLimitTier": "default_claude_max_20x", "planDisplayName": "Ultra"}}"#)
        let (model, defaults, suite) = try makeModel(planURL: url)
        defer { defaults.removePersistentDomain(forName: suite) }
        model.refreshPlan()
        for _ in 0..<100 where model.claudePlan == nil { try await Task.sleep(for: .milliseconds(20)) }
        let snapshot = model.snapshot(agentsEnabled: true, now: .now)
        XCTAssertEqual(snapshot.plans[.claude]?.title, "Claude Max 20x")
        XCTAssertEqual(snapshot.plans[.claude]?.subtitle, "Ultra")
        XCTAssertNil(snapshot.plans[.codex])
    }

    // MARK: Çizelge yardımcıları

    func testTimelineHelpers() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resets = now.addingTimeInterval(2 * 3600) // 5 saatlik pencerenin 3 saati geçti
        let forecast = LimitForecast(fillsAt: now.addingTimeInterval(3600), resetsAt: resets, ratePerHour: 20, usedPercent: 80, basedOn: now)
        let window = LimitWindowDisplay(kind: .fiveHour, usedPercent: 80, resetsAt: resets, isReset: false, isStale: false, level: .warning,
                                        warnAt: 80, criticalAt: 95, forecast: forecast)
        XCTAssertEqual(window.startsAt, resets.addingTimeInterval(-5 * 3600))
        XCTAssertEqual(try XCTUnwrap(window.forecastFraction), 0.8, accuracy: 0.001)
        XCTAssertEqual(window.paceText(now: now), "Süreden hızlı gidiyor") // %80 kullanım, %60 süre
        var calm = window
        calm.usedPercent = 20
        calm.forecast = nil
        XCTAssertEqual(calm.paceText(now: now), "Rahat gidiyor")
        XCTAssertNil(calm.forecastFraction)
        var stale = window
        stale.isStale = true
        XCTAssertNil(stale.paceText(now: now))
        var late = window
        late.forecast = LimitForecast(fillsAt: resets.addingTimeInterval(60), resetsAt: resets, ratePerHour: 1, usedPercent: 80, basedOn: now)
        XCTAssertNil(late.forecastFraction, "yenilenmeden sonra dolacaksa çizelgede işaret yok")
    }
}
