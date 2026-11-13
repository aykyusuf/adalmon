import XCTest
@testable import Adalmon

/// Çok oturumlu limit birleştirme: eski oturumun düşük değeri göstergeyi geri sarmaz.
@MainActor
final class LimitMergeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func claude(five: (Double, TimeInterval)? = nil, weekly: (Double, TimeInterval)? = nil, observed: Date? = nil) -> ProviderLimits {
        ProviderLimits(source: .claude,
                       fiveHour: five.map { LimitWindow(usedPercent: $0.0, resetsAt: now.addingTimeInterval($0.1)) },
                       weekly: weekly.map { LimitWindow(usedPercent: $0.0, resetsAt: now.addingTimeInterval($0.1)) },
                       observedAt: observed ?? now)
    }

    func testLowerValueForSameResetIsIgnoredEntirely() {
        let current = claude(weekly: (11, 86_400))
        XCTAssertNil(LimitMerge.monotonic(current: current, incoming: claude(weekly: (7, 86_400))), "11 sonra 7 (aynı reset): yok sayılır")
        XCTAssertNil(LimitMerge.monotonic(current: current, incoming: claude(weekly: (7, 86_400 + 30))), "±60 sn tolerans içinde aynı pencere")
    }

    func testHigherOrEqualValueForSameResetIsAccepted() throws {
        let current = claude(weekly: (7, 86_400))
        XCTAssertEqual(try XCTUnwrap(LimitMerge.monotonic(current: current, incoming: claude(weekly: (11, 86_400)))).weekly?.usedPercent, 11)
        XCTAssertEqual(try XCTUnwrap(LimitMerge.monotonic(current: current, incoming: claude(weekly: (7, 86_400)))).weekly?.usedPercent, 7)
    }

    func testNewerResetStartsNewWindowAndAcceptsLowerValue() throws {
        let current = claude(weekly: (11, 86_400))
        let merged = try XCTUnwrap(LimitMerge.monotonic(current: current, incoming: claude(weekly: (2, 86_400 + 7 * 86_400))))
        XCTAssertEqual(merged.weekly?.usedPercent, 2)
    }

    func testOlderResetIsIgnored() {
        let current = claude(weekly: (11, 7 * 86_400))
        XCTAssertNil(LimitMerge.monotonic(current: current, incoming: claude(weekly: (30, 86_400))))
    }

    func testWindowsAreMergedIndependently() throws {
        let current = claude(five: (40, 3600), weekly: (11, 86_400))
        // 5 saatlik arttı, haftalık eski oturumdan düşük geldi: 5 saatlik kabul, haftalık mevcut kalır.
        let merged = try XCTUnwrap(LimitMerge.monotonic(current: current, incoming: claude(five: (55, 3600), weekly: (7, 86_400))))
        XCTAssertEqual(merged.fiveHour?.usedPercent, 55)
        XCTAssertEqual(merged.weekly?.usedPercent, 11)
    }

    func testModelKeepsHigherValueAndObservedAtWhenStaleSessionReports() throws {
        let suite = "LimitMergeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SubscriptionLimitsModel(defaults: defaults, usageStore: ModelUsageStore(claudeRoot: URL(filePath: "/nonexistent-a"), codexRoot: URL(filePath: "/nonexistent-b")), live: false)
        model.ingestClaude(claude(weekly: (11, 86_400)), now: now)
        model.ingestClaude(claude(weekly: (7, 86_400)), now: now.addingTimeInterval(15))
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 11)
        XCTAssertEqual(model.claude?.observedAt, now, "yok sayılan değer observedAt'i güncellemez")
        model.ingestClaude(claude(weekly: (12, 86_400)), now: now.addingTimeInterval(30))
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 12)
        model.ingestClaude(claude(weekly: (2, 86_400 + 7 * 86_400)), now: now.addingTimeInterval(45))
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 2, "yeni reset: yeni pencere")
        model.ingestClaude(claude(weekly: (40, 86_400)), now: now.addingTimeInterval(60))
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 2, "eski reset ile gelen yok sayılır")
    }

    // MARK: Oturum başına seçim (ClaudeSessionLimits)

    private func at(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    /// 7↔11: A aktif (7→9→11), B boşta hep 7 yollar → gösterge 11'de kalır, zıplamaz.
    func testIdleSessionResendingOldValueDoesNotFlip() {
        var sessions = ClaudeSessionLimits()
        XCTAssertEqual(sessions.ingest(claude(weekly: (7, 86_400)), sessionID: "A", now: at(0))?.weekly?.usedPercent, 7)
        XCTAssertEqual(sessions.ingest(claude(weekly: (7, 86_400)), sessionID: "B", now: at(5))?.weekly?.usedPercent, 7)
        var shown: [Double] = []
        for (t, value) in [(10.0, 9.0), (20, 11)] {
            shown.append(sessions.ingest(claude(weekly: (value, 86_400)), sessionID: "A", now: at(t))?.weekly?.usedPercent ?? -1)
            for k in 1...3 { shown.append(sessions.ingest(claude(weekly: (7, 86_400)), sessionID: "B", now: at(t + Double(k)))?.weekly?.usedPercent ?? -1) }
        }
        XCTAssertEqual(shown, [9, 9, 9, 9, 11, 11, 11, 11])
    }

    /// Limit sıfırlaması: yenilenme anı aynı, yüzde düşer. Kalıcı (oturumsuz) 79'u ilk oturum değeri geçer; sonra artış izlenir.
    func testLimitResetDropWithSameResetsAtIsShown() {
        var sessions = ClaudeSessionLimits(legacy: claude(weekly: (79, 86_400), observed: at(-3 * 3600)))
        XCTAssertEqual(sessions.display()?.weekly?.usedPercent, 79)
        XCTAssertEqual(sessions.ingest(claude(weekly: (27, 86_400)), sessionID: "A", now: at(0))?.weekly?.usedPercent, 27)
        XCTAssertEqual(sessions.ingest(claude(weekly: (35, 86_400)), sessionID: "A", now: at(60))?.weekly?.usedPercent, 35)
        // Oturumsuz (eski sarmalayıcı) mesaj oturum değerini geçemez.
        XCTAssertEqual(sessions.ingest(claude(weekly: (80, 86_400)), sessionID: nil, now: at(70))?.weekly?.usedPercent, 35)
        // Sıfırlamadan önce görülmüş, değeri değişmeyen oturum aynı değeri yollar: değişen oturum kazanır.
        XCTAssertEqual(sessions.ingest(claude(weekly: (35, 86_400)), sessionID: "A", now: at(80))?.weekly?.usedPercent, 35)
    }

    /// Bir oturumun tek seferlik düşüşü (aynı oturumda değer değişti) kabul edilir: "yalnızca artar" kuralı yok.
    func testSameSessionDecreaseIsAccepted() {
        var sessions = ClaudeSessionLimits()
        sessions.ingest(claude(weekly: (79, 86_400)), sessionID: "A", now: at(0))
        XCTAssertEqual(sessions.ingest(claude(weekly: (27, 86_400)), sessionID: "A", now: at(15))?.weekly?.usedPercent, 27)
    }

    /// Adalmon yeniden açılınca her oturum değerini rastgele sırayla yeniden yollar: boşta oturumun düşük ilk değeri geri saramaz.
    func testRestartResendOrderDoesNotRewind() {
        var sessions = ClaudeSessionLimits(legacy: claude(weekly: (11, 86_400)))
        XCTAssertEqual(sessions.ingest(claude(weekly: (11, 86_400)), sessionID: "A", now: at(0))?.weekly?.usedPercent, 11)
        XCTAssertEqual(sessions.ingest(claude(weekly: (7, 86_400)), sessionID: "B", now: at(3))?.weekly?.usedPercent, 11, "B'nin ilk (düşük) değeri değişiklik sayılmaz")
        XCTAssertEqual(sessions.ingest(claude(weekly: (12, 86_400)), sessionID: "A", now: at(30))?.weekly?.usedPercent, 12)
        // Yeni açılan oturumun ilk değeri gösterilenden düşük değilse tazedir ve kazanır.
        XCTAssertEqual(sessions.ingest(claude(weekly: (13, 86_400)), sessionID: "C", now: at(40))?.weekly?.usedPercent, 13)
        // Bilinen belirsizlik: sıfırlamadan önce açılıp hiç değeri değişmemiş oturumun ilk mesajı (79) yüksek olduğu için gösterilir;
        // aktif oturumun bir sonraki değişikliğinde düzelir.
        var reset = ClaudeSessionLimits(legacy: claude(weekly: (79, 86_400)))
        reset.ingest(claude(weekly: (27, 86_400)), sessionID: "A", now: at(0))
        XCTAssertEqual(reset.ingest(claude(weekly: (79, 86_400)), sessionID: "B", now: at(2))?.weekly?.usedPercent, 79)
        XCTAssertEqual(reset.ingest(claude(weekly: (28, 86_400)), sessionID: "A", now: at(20))?.weekly?.usedPercent, 28)
    }

    /// Yeni pencere (yenilenme anı >60 sn ileri) her zaman kazanır; eski pencerenin oturumu son değişen olsa bile.
    func testNewerWindowAlwaysWinsPerWindowKind() throws {
        var sessions = ClaudeSessionLimits()
        sessions.ingest(claude(five: (90, 600), weekly: (40, 86_400)), sessionID: "old", now: at(0))
        sessions.ingest(claude(five: (3, 600 + 5 * 3600), weekly: (40, 86_400)), sessionID: "new", now: at(10))
        let shown = try XCTUnwrap(sessions.ingest(claude(five: (91, 600), weekly: (41, 86_400)), sessionID: "old", now: at(20)))
        XCTAssertEqual(shown.fiveHour?.usedPercent, 3, "yeni 5 saatlik pencere kazanır")
        XCTAssertEqual(shown.weekly?.usedPercent, 41, "haftalık ayrı: değeri en son değişen oturum")
        XCTAssertEqual(shown.observedAt, at(20))
    }

    /// Oturum değeri olmayan pencere için kalıcı/oturumsuz değer kullanılır.
    func testLegacyFillsWindowsSessionsDoNotReport() throws {
        var sessions = ClaudeSessionLimits(legacy: claude(five: (50, 3600), weekly: (20, 86_400)))
        let shown = try XCTUnwrap(sessions.ingest(claude(weekly: (22, 86_400)), sessionID: "A", now: at(5)))
        XCTAssertEqual(shown.fiveHour?.usedPercent, 50)
        XCTAssertEqual(shown.weekly?.usedPercent, 22)
    }

    /// Değişmeyen değeri yeniden yollayan kazanan oturum ve hook etkinliği tazeliği ilerletir; kaybeden ya da bilinmeyen oturum ilerletmez.
    func testFreshnessFromWinnerMessagesAndActivity() {
        var sessions = ClaudeSessionLimits()
        sessions.ingest(claude(weekly: (11, 86_400)), sessionID: "A", now: at(0))
        sessions.ingest(claude(weekly: (7, 86_400)), sessionID: "B", now: at(1))
        XCTAssertEqual(sessions.display()?.observedAt, at(0))
        XCTAssertEqual(sessions.ingest(claude(weekly: (7, 86_400)), sessionID: "B", now: at(100))?.observedAt, at(0), "kaybeden oturum tazelemez")
        XCTAssertEqual(sessions.ingest(claude(weekly: (11, 86_400)), sessionID: "A", now: at(200))?.observedAt, at(200), "kazanan, değişmese de tazeler")
        XCTAssertEqual(sessions.noteActivity(sessionID: "A", now: at(900))?.observedAt, at(900))
        XCTAssertNil(sessions.noteActivity(sessionID: "unknown", now: at(950)))
        XCTAssertEqual(sessions.display()?.weekly?.usedPercent, 11)
    }

    /// Hook etkinliği oturumu tek başına canlı tutamaz: sarmalayıcıdan 24 saattir mesaj yoksa etkinlik tazeliği ilerletmez.
    func testActivityAloneCannotKeepDataFreshForever() {
        var sessions = ClaudeSessionLimits()
        sessions.ingest(claude(weekly: (11, 86_400)), sessionID: "A", now: at(0))
        var last: Date?
        for hour in 1...30 {
            if let shown = sessions.noteActivity(sessionID: "A", now: at(Double(hour) * 3600)) { last = shown.observedAt }
        }
        XCTAssertEqual(last, at(23 * 3600), "24 saatten sonra etkinlik tazelemez")
        XCTAssertTrue(sessions.sessions.isEmpty)
        XCTAssertEqual(sessions.display()?.weekly?.usedPercent, 11, "son değer legacy olarak kalır")
        XCTAssertEqual(sessions.display()?.observedAt, at(23 * 3600))
    }

    func testPruneAndCap() throws {
        var sessions = ClaudeSessionLimits()
        sessions.ingest(claude(weekly: (30, 86_400)), sessionID: "old", now: at(0))
        // 24 saat sonra eski oturum unutulur; hepsi unutulursa son gösterilen değer korunur (eski kalıcı değere dönülmez).
        sessions.ingest(claude(weekly: (31, 86_400)), sessionID: "fresh", now: at(25 * 3600))
        XCTAssertEqual(sessions.sessions.keys.sorted(), ["fresh"])
        var lone = ClaudeSessionLimits(legacy: claude(weekly: (79, 86_400)))
        lone.ingest(claude(weekly: (27, 86_400)), sessionID: "A", now: at(0))
        XCTAssertEqual(lone.ingest(claude(weekly: (27, 86_400)), sessionID: nil, now: at(25 * 3600))?.weekly?.usedPercent, 27)
        XCTAssertTrue(lone.sessions.isEmpty)
        for i in 0..<20 { sessions.ingest(claude(weekly: (Double(40 + i), 86_400)), sessionID: "s\(i)", now: at(26 * 3600 + Double(i))) }
        XCTAssertEqual(sessions.sessions.count, ClaudeSessionLimits.maxSessions)
        XCTAssertNotNil(sessions.sessions["s19"])
        XCTAssertNil(sessions.sessions["fresh"], "en eski duyulan atılır")
    }

    func testModelShowsResetDropAndActivityRefreshesFreshness() throws {
        let suite = "LimitMergeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func makeModel() -> SubscriptionLimitsModel {
            SubscriptionLimitsModel(defaults: defaults, usageStore: ModelUsageStore(claudeRoot: URL(filePath: "/nonexistent-a"), codexRoot: URL(filePath: "/nonexistent-b")), live: false)
        }
        let first = makeModel()
        first.ingestClaude(claude(weekly: (79, 86_400)), now: at(0))
        // Yeniden açılış: kalıcı 79 (oturumsuz) + oturum A sıfırlama sonrası 27 → 35.
        let model = makeModel()
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 79)
        model.ingestClaude(claude(weekly: (27, 86_400)), sessionID: "A", now: at(3 * 3600))
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 27)
        model.ingestClaude(claude(weekly: (7, 86_400)), sessionID: "B", now: at(3 * 3600 + 5))
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 27, "boşta oturumun düşük ilk değeri geçemez")
        model.ingestClaude(claude(weekly: (35, 86_400)), sessionID: "A", now: at(3 * 3600 + 30))
        XCTAssertEqual(model.claude?.weekly?.usedPercent, 35)
        XCTAssertEqual(makeModel().claude?.weekly?.usedPercent, 35, "gösterilen değer kalıcı")
        // Hook etkinliği: değer değişmeden tazelik ilerler (en çok dakikada bir).
        model.noteClaudeActivity(sessionID: "A", now: at(3 * 3600 + 50))
        XCTAssertEqual(model.claude?.observedAt, at(3 * 3600 + 30), "dakikadan kısa: yazılmaz")
        model.noteClaudeActivity(sessionID: "A", now: at(3 * 3600 + 40 * 60))
        XCTAssertEqual(model.claude?.observedAt, at(3 * 3600 + 40 * 60))
        XCTAssertFalse(try XCTUnwrap(model.claude).isStale(now: at(3 * 3600 + 41 * 60)))
        model.noteClaudeActivity(sessionID: "B", now: at(5 * 3600))
        XCTAssertEqual(model.claude?.observedAt, at(3 * 3600 + 40 * 60), "kaybeden oturumun etkinliği tazelemez")
        model.noteClaudeActivity(sessionID: "zzz", now: at(5 * 3600))
        XCTAssertEqual(model.claude?.observedAt, at(3 * 3600 + 40 * 60))
    }

    // MARK: Codex pasif kaynak

    func testCodexRolloutDecreaseAcceptedOnlyFromNewerEvent() throws {
        func codex(_ used: Double, observed: TimeInterval) -> ProviderLimits {
            ProviderLimits(source: .codex, weekly: LimitWindow(usedPercent: used, resetsAt: at(86_400)), observedAt: at(observed))
        }
        let current = codex(79, observed: 0)
        XCTAssertEqual(try XCTUnwrap(LimitMerge.codexUpdate(current: current, incoming: codex(27, observed: 60))).weekly?.usedPercent, 27, "daha yeni olay: sıfırlama")
        XCTAssertNil(LimitMerge.codexUpdate(current: current, incoming: codex(27, observed: 0)), "aynı olay düşüremez")
        XCTAssertNil(LimitMerge.codexUpdate(current: current, incoming: codex(27, observed: -60)), "eski olay düşüremez")
    }
}
