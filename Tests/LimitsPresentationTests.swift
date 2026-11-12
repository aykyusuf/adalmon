import XCTest
@testable import Adalmon

/// Limitler ekranlarının (Genel bakış kartı, Limitler sayfası, panel kartı) saf gösterim mantığı: biçim, öne çıkan pencere, boş durumlar.
@MainActor
final class LimitsPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let thresholds = LimitAlertThresholds()

    private func window(_ used: Double, resetsIn: TimeInterval? = 2 * 3600) -> LimitWindow {
        LimitWindow(usedPercent: used, resetsAt: resetsIn.map { now.addingTimeInterval($0) })
    }

    private func claude(five: Double? = 62, weekly: Double? = 35, age: TimeInterval = 0, fiveResetsIn: TimeInterval? = 2 * 3600) -> ProviderLimits {
        ProviderLimits(source: .claude, fiveHour: five.map { window($0, resetsIn: fiveResetsIn) },
                       weekly: weekly.map { window($0, resetsIn: 3 * 86_400) }, observedAt: now.addingTimeInterval(-age))
    }

    private func codex(five: Double? = 80, weekly: Double? = 20, age: TimeInterval = 0, credits: Double? = nil) -> ProviderLimits {
        ProviderLimits(source: .codex, fiveHour: five.map { window($0) }, weekly: weekly.map { window($0, resetsIn: 86_400) },
                       observedAt: now.addingTimeInterval(-age), creditsBalance: credits)
    }

    private func sections(_ providers: [ProviderLimits], connected: Bool = true, agents: Bool = true, codexOn: Bool = true,
                          forecast: ((ProviderLimits, LimitWindowKind) -> LimitForecast?)? = nil) -> [LimitSection] {
        LimitsPresentation.sections(providers: providers, claudeConnected: connected, agentsEnabled: agents, codexEnabled: codexOn,
                                    thresholds: thresholds, now: now, forecast: forecast ?? { _, _ in nil })
    }

    private func forecast(rate: Double = 12, fillsIn: TimeInterval = 3600) -> LimitForecast {
        LimitForecast(fillsAt: now.addingTimeInterval(fillsIn), resetsAt: now.addingTimeInterval(2 * 3600), ratePerHour: rate,
                      usedPercent: 62, basedOn: now)
    }

    // MARK: Pencere

    func testWindowFormatsPercentAndTone() throws {
        let s = sections([claude(five: 62, weekly: 96), codex()])
        let c = try XCTUnwrap(s[0].display)
        let five = try XCTUnwrap(c.window(.fiveHour)), weekly = try XCTUnwrap(c.window(.weekly))
        XCTAssertEqual(five.percentText, "%62")
        XCTAssertEqual(five.numberText, "62")
        XCTAssertEqual(five.fraction, 0.62, accuracy: 1e-9)
        XCTAssertEqual(five.tone, .normal)
        XCTAssertEqual(five.statusText, "Normal")
        XCTAssertEqual(weekly.tone, .critical)
        XCTAssertEqual(weekly.statusText, "Kritik")
        let warn = try XCTUnwrap(s[1].display?.window(.fiveHour))
        XCTAssertEqual(warn.tone, .warning, "%80 varsayılan eşikte uyarı")
        XCTAssertEqual(LimitsPresentation.thresholdText(warn), "Uyarı %80 · Kritik %95")
    }

    func testResetWindowShowsDashAndZeroFill() throws {
        let s = sections([claude(five: 90, weekly: 10, fiveResetsIn: -60)])
        let five = try XCTUnwrap(s[0].display?.window(.fiveHour))
        XCTAssertTrue(five.isReset)
        XCTAssertEqual(five.percentText, "—")
        XCTAssertEqual(five.numberText, "—")
        XCTAssertEqual(five.fraction, 0)
        XCTAssertEqual(five.tone, .muted)
        XCTAssertEqual(five.statusText, "Yenilendi")
        XCTAssertNil(five.countdownText(now: now))
        XCTAssertNil(five.forecast, "yenilenmiş pencerede tahmin yok")
    }

    func testStaleProviderIsMutedAndDropsForecast() throws {
        let s = sections([claude(age: 3 * 3600)], forecast: { _, _ in self.forecast() })
        let display = try XCTUnwrap(s[0].display)
        XCTAssertTrue(display.isStale)
        XCTAssertEqual(display.freshnessText(now: now), "Bayat · son veri 3 sa önce")
        XCTAssertTrue(display.windows.allSatisfy { $0.tone == .muted && $0.forecast == nil })
        let fresh = try XCTUnwrap(sections([claude(age: 120)])[0].display)
        XCTAssertEqual(fresh.freshnessText(now: now), "Güncel · 2 dk önce")
    }

    func testCountdownAndElapsed() throws {
        let five = try XCTUnwrap(sections([claude(five: 10, fiveResetsIn: 2 * 3600 + 10 * 60)])[0].display?.window(.fiveHour))
        XCTAssertEqual(five.countdownText(now: now), "2 sa 10 dk")
        XCTAssertEqual(try XCTUnwrap(five.elapsedFraction(now: now)), 1 - (2 * 3600 + 600) / (5 * 3600), accuracy: 1e-9)
        let weekly = try XCTUnwrap(sections([claude()])[0].display?.window(.weekly))
        XCTAssertEqual(weekly.countdownText(now: now), "3 gün")
        XCTAssertEqual(try XCTUnwrap(weekly.elapsedFraction(now: now)), 1 - 3.0 / 7, accuracy: 1e-9)
        let soon = try XCTUnwrap(sections([claude(five: 10, fiveResetsIn: 20)])[0].display?.window(.fiveHour))
        XCTAssertEqual(soon.countdownText(now: now), "1 dk", "yenilenmeden önceki son saniyeler 1 dk")
        let unknown = try XCTUnwrap(sections([claude(five: 10, fiveResetsIn: nil)])[0].display?.window(.fiveHour))
        XCTAssertNil(unknown.countdownText(now: now))
        XCTAssertNil(unknown.elapsedFraction(now: now))
        let longAgo = try XCTUnwrap(sections([claude(five: 10, fiveResetsIn: 30 * 3600)])[0].display?.window(.fiveHour))
        XCTAssertEqual(try XCTUnwrap(longAgo.elapsedFraction(now: now)), 0, "5 saatten uzak yenilenme 0'a kenetlenir")
    }

    func testRateAndForecastText() throws {
        let s = sections([claude()], forecast: { _, kind in kind == .fiveHour ? self.forecast(rate: 12.4) : self.forecast(rate: 1.44) })
        let five = try XCTUnwrap(s[0].display?.window(.fiveHour)), weekly = try XCTUnwrap(s[0].display?.window(.weekly))
        XCTAssertEqual(five.rateText, "%12/sa")
        XCTAssertEqual(weekly.rateText, "%1,4/sa")
        let text = try XCTUnwrap(five.forecastText(now: now))
        XCTAssertTrue(text.hasPrefix("Bu hızla ~") && text.hasSuffix(" dolar"), text)
        XCTAssertNil(try XCTUnwrap(sections([claude()])[0].display?.window(.fiveHour)).rateText, "tahmin yoksa hız yok")
    }

    // MARK: Bölümler ve boş durumlar

    func testEmptyStates() {
        XCTAssertEqual(sections([], connected: false)[0].state, .empty(.claudeNotConnected))
        XCTAssertEqual(sections([], connected: true)[0].state, .empty(.claudeWaiting))
        XCTAssertEqual(sections([claude()], agents: false)[0].state, .empty(.agentsDisabled), "ajanlar kapalıyken Claude verisi gösterilmez")
        XCTAssertEqual(sections([claude()], codexOn: false)[1].state, .empty(.codexDisabled))
        XCTAssertEqual(sections([claude()])[1].state, .empty(.codexNoData))
        XCTAssertEqual(sections([], connected: false).map(\.source), [.claude, .codex], "her zaman iki bölüm")
        XCTAssertNotNil(sections([codex()], agents: false)[1].display, "ajanlar kapalıyken Codex görünür")
    }

    func testEmptyReasonActions() {
        XCTAssertEqual(LimitEmptyReason.claudeNotConnected.actionTitle, "Bağla")
        XCTAssertEqual(LimitEmptyReason.agentsDisabled.actionTitle, "Ayarlar'ı aç")
        XCTAssertNil(LimitEmptyReason.claudeWaiting.actionTitle)
        XCTAssertNil(LimitEmptyReason.codexNoData.actionTitle)
        for reason in [LimitEmptyReason.agentsDisabled, .claudeNotConnected, .claudeWaiting, .codexDisabled, .codexNoData] {
            XCTAssertFalse(reason.title.isEmpty)
            XCTAssertFalse(reason.detail.isEmpty)
        }
    }

    func testCreditsKept() throws {
        XCTAssertEqual(try XCTUnwrap(sections([codex(credits: 12.5)])[1].display).creditsBalance, 12.5)
    }

    // MARK: Öne çıkan pencere

    func testFeaturedIsHighestUsage() throws {
        let snap = LimitsSnapshot(sections: sections([claude(five: 62, weekly: 35), codex(five: 80, weekly: 20)]), thresholds: thresholds, now: now)
        let top = try XCTUnwrap(snap.featured)
        XCTAssertEqual(top.source, .codex)
        XCTAssertEqual(top.window.kind, .fiveHour)
        XCTAssertTrue(snap.hasData)
    }

    func testFeaturedPrefersFreshOverStaleAndSkipsReset() throws {
        let staleHigh = claude(five: 99, weekly: 98, age: 3 * 3600)
        let snap = LimitsSnapshot(sections: sections([staleHigh, codex(five: 30, weekly: 10)]), thresholds: thresholds, now: now)
        XCTAssertEqual(snap.featured?.source, .codex, "taze veri varken bayat pencere öne çıkmaz")
        XCTAssertEqual(snap.featured?.window.usedPercent, 30)
        let onlyStale = LimitsSnapshot(sections: sections([staleHigh]), thresholds: thresholds, now: now)
        XCTAssertEqual(onlyStale.featured?.window.usedPercent, 99, "hepsi bayatsa yine en yüksek")
        let reset = LimitsSnapshot(sections: sections([claude(five: 99, weekly: 5, fiveResetsIn: -1)]), thresholds: thresholds, now: now)
        XCTAssertEqual(reset.featured?.window.kind, .weekly, "yenilenmiş pencere öne çıkmaz")
        let empty = LimitsSnapshot(sections: sections([]), thresholds: thresholds, now: now)
        XCTAssertNil(empty.featured)
        XCTAssertFalse(empty.hasData)
    }

    func testFeaturedTieKeepsFirst() throws {
        let snap = LimitsSnapshot(sections: sections([claude(five: 50, weekly: 50), codex(five: 50, weekly: 50)]), thresholds: thresholds, now: now)
        XCTAssertEqual(snap.featured?.source, .claude)
        XCTAssertEqual(snap.featured?.window.kind, .fiveHour)
    }

    // MARK: Kart satırı

    func testCardCaptionVariants() {
        func snap(_ providers: [ProviderLimits], f: ((ProviderLimits, LimitWindowKind) -> LimitForecast?)? = nil) -> LimitsSnapshot {
            LimitsSnapshot(sections: sections(providers, forecast: f), thresholds: thresholds, now: now)
        }
        XCTAssertEqual(LimitsPresentation.cardCaption(snap([claude(five: 62, weekly: 35)])), "Claude 5 sa · 2 sa")
        XCTAssertEqual(LimitsPresentation.cardCaption(snap([claude(five: 10, weekly: 70)])), "Claude Haftalık · 3 gün")
        let forecasted = LimitsPresentation.cardCaption(snap([claude()], f: { _, kind in kind == .fiveHour ? self.forecast() : nil }))
        XCTAssertTrue(forecasted?.hasPrefix("Claude ~") == true && forecasted?.hasSuffix(" dolar") == true, forecasted ?? "nil")
        XCTAssertEqual(LimitsPresentation.cardCaption(snap([claude(age: 3 * 3600)])), "Son veri 3 sa önce")
        XCTAssertNil(LimitsPresentation.cardCaption(snap([])))
        XCTAssertEqual(LimitsPresentation.cardCaption(snap([claude(five: 10, weekly: nil, fiveResetsIn: nil)])), "Claude 5 sa")
    }

    func testThresholdTextOrdersSwappedValues() throws {
        var t = LimitAlertThresholds()
        t.fiveHourWarn = 95
        t.fiveHourCritical = 80
        let s = LimitsPresentation.sections(providers: [claude()], claudeConnected: true, agentsEnabled: true, codexEnabled: true,
                                            thresholds: t, now: now, forecast: { _, _ in nil })
        let five = try XCTUnwrap(s[0].display?.window(.fiveHour))
        XCTAssertEqual(LimitsPresentation.thresholdText(five), "Uyarı %80 · Kritik %95", "ters girilen eşikler sıralanır (LimitAlertThresholds ile aynı kural)")
    }

    // MARK: Model

    func testModelSnapshotReadsProvidersAndConnection() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: "adalmon-limits-pres-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = "adalmon.limits.pres.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let binder = ClaudeStatusLineBinder(settingsURL: temp.appending(path: "claude/settings.json"),
                                            supportDirectory: temp.appending(path: "support", directoryHint: .isDirectory),
                                            configURL: temp.appending(path: "config.json"))
        let model = SubscriptionLimitsModel(defaults: defaults, binder: binder, codexReader: CodexRolloutReader(root: temp), live: false)
        let empty = model.snapshot(agentsEnabled: true, now: .now)
        XCTAssertEqual(empty.sections[0].state, .empty(.claudeNotConnected))
        let at = Date.now
        model.ingestClaude(ProviderLimits(source: .claude, fiveHour: LimitWindow(usedPercent: 41, resetsAt: at.addingTimeInterval(3600)), observedAt: at), now: at)
        let filled = model.snapshot(agentsEnabled: true, now: at)
        XCTAssertEqual(filled.sections[0].display?.window(.fiveHour)?.percentText, "%41")
        XCTAssertEqual(filled.featured?.source, .claude)
        XCTAssertEqual(model.snapshot(agentsEnabled: false, now: at).sections[0].state, .empty(.agentsDisabled))
    }

    // MARK: Gelmeyen pencere gizlenir (ör. Claude Ultra'da 5 saatlik yok)

    func testMissingFiveHourWindowIsNotShownAnywhere() throws {
        let providers = [claude(five: nil, weekly: 35), codex(five: nil, weekly: 20)]
        let s = sections(providers)
        let display = try XCTUnwrap(s[0].display)
        XCTAssertEqual(display.windows.map(\.kind), [.weekly], "5 saatlik pencere için boş kutu/halka üretilmez")
        XCTAssertNil(display.window(.fiveHour))
        let snapshot = LimitsSnapshot(sections: s, thresholds: thresholds, now: now)
        XCTAssertEqual(snapshot.visibleKinds, [.weekly])
        XCTAssertEqual(LimitsPresentation.timelineRows(snapshot).map(\.window.kind), [.weekly, .weekly])
    }

    func testVisibleKindsKeepsWindowAnyProviderHas() {
        let s = sections([claude(five: nil, weekly: 35), codex(five: 80, weekly: 20)])
        let snapshot = LimitsSnapshot(sections: s, thresholds: thresholds, now: now)
        XCTAssertEqual(snapshot.visibleKinds, [.fiveHour, .weekly])
        XCTAssertEqual(LimitsPresentation.timelineRows(snapshot).map { "\($0.source.rawValue)-\($0.window.kind.rawValue)" },
                       ["claude-weekly", "codex-fiveHour", "codex-weekly"])
    }

    func testVisibleKindsFallsBackToBothWhenNoData() {
        let snapshot = LimitsSnapshot(sections: sections([], connected: false), thresholds: thresholds, now: now)
        XCTAssertEqual(snapshot.visibleKinds, LimitWindowKind.allCases)
        XCTAssertTrue(LimitsPresentation.timelineRows(snapshot).isEmpty)
    }

    func testCardCaptionAndFeaturedUseOnlyExistingWindows() throws {
        let snapshot = LimitsSnapshot(sections: sections([claude(five: nil, weekly: 35)]), thresholds: thresholds, now: now)
        let featured = try XCTUnwrap(snapshot.featured)
        XCTAssertEqual(featured.window.kind, .weekly)
        XCTAssertEqual(LimitsPresentation.cardCaption(snapshot)?.contains("5 sa"), false)
    }

    func testModelUsageTravelsInSnapshotAndDefaultsToEmpty() {
        let snapshot = LimitsSnapshot(sections: sections([claude()]), thresholds: thresholds, now: now)
        XCTAssertTrue(snapshot.modelUsage.isEmpty)
    }
}
