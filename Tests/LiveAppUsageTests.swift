import XCTest
@testable import Adalmon

/// Canlı uygulama listesi: aralık toplama/sıralama ve satır komutu → hız sınırı/engel eşlemesi.
/// Gerçek ağ kuralı uygulanmaz: komutlar sahte `LiveAppControls` kaydına gider.
final class LiveAppUsageTests: XCTestCase {
    private let chrome = "/Applications/Google Chrome.app"
    private let slack = "/Applications/Slack.app"
    private let mds = "/System/Library/Frameworks/CoreServices.framework/mds"
    private let m0 = 29_000_000 // bir Unix dakikası

    // MARK: Toplama ve sıralama

    func testSixtySecondRangeUsesSecondRingAndExpiresAfterSixtySeconds() {
        var h = LiveUsageHistory()
        h.advance(seconds: 1)
        h.record(app: chrome, bytesIn: 1_000, bytesOut: 100, mobile: false, minute: m0)
        XCTAssertEqual(h.rows(range: .sec60, interface: .all, nowMinute: m0).map(\.bytes), [1_100])
        h.advance(seconds: 59)
        XCTAssertEqual(h.rows(range: .sec60, interface: .all, nowMinute: m0).count, 1, "59 sn sonra hâlâ pencerede")
        h.advance(seconds: 1)
        XCTAssertTrue(h.rows(range: .sec60, interface: .all, nowMinute: m0).isEmpty, "60 sn sonra düşer")
        // Dakika kovası ise kalır.
        XCTAssertEqual(h.rows(range: .min5, interface: .all, nowMinute: m0 + 1).first?.bytes, 1_100)
    }

    func testMinuteRangesIncludeExactlyTheLastNMinutes() {
        var h = LiveUsageHistory()
        let now = m0 + 59
        // Her dakikada 1 byte: dakika (now - k) için k = 0…59, artı 61 dk önce bir kayıt.
        for k in 0..<60 { h.record(app: chrome, bytesIn: 1, bytesOut: 0, mobile: false, minute: now - k) }
        h.record(app: chrome, bytesIn: 1_000, bytesOut: 0, mobile: false, minute: now - 61)
        XCTAssertEqual(h.totals(range: .min5, nowMinute: now)[chrome]?.down, 5)
        XCTAssertEqual(h.totals(range: .min15, nowMinute: now)[chrome]?.down, 15)
        XCTAssertEqual(h.totals(range: .min30, nowMinute: now)[chrome]?.down, 30)
        XCTAssertEqual(h.totals(range: .hour1, nowMinute: now)[chrome]?.down, 60)
        h.prune(nowMinute: now)
        XCTAssertEqual(h.totals(range: .hour1, nowMinute: now + 100)[chrome], nil, "60 dk'dan eski kovalar atılır")
    }

    func testRowsSortedByBytesDescendingThenNameAndLimited() {
        var h = LiveUsageHistory()
        h.record(app: slack, bytesIn: 500, bytesOut: 0, mobile: false, minute: m0)
        h.record(app: chrome, bytesIn: 900, bytesOut: 100, mobile: false, minute: m0)
        h.record(app: mds, bytesIn: 500, bytesOut: 0, mobile: false, minute: m0)
        let rows = h.rows(range: .min5, interface: .all, nowMinute: m0)
        XCTAssertEqual(rows.map(\.app), [chrome, slack, mds], "eşit byte'ta anahtar sırası (Slack < /System)")
        XCTAssertEqual(rows.first?.down, 900)
        XCTAssertEqual(rows.first?.up, 100)
        XCTAssertEqual(h.rows(range: .min5, interface: .all, nowMinute: m0, limit: 2).count, 2)
    }

    func testInterfaceFilterSplitsMobileAndWifi() {
        var h = LiveUsageHistory()
        h.record(app: chrome, bytesIn: 1_000, bytesOut: 10, mobile: true, minute: m0)
        h.record(app: chrome, bytesIn: 3_000, bytesOut: 30, mobile: false, minute: m0)
        h.record(app: slack, bytesIn: 50, bytesOut: 0, mobile: false, minute: m0)
        let mobile = h.rows(range: .min15, interface: .mobile, nowMinute: m0)
        XCTAssertEqual(mobile.map(\.app), [chrome], "Wi-Fi'de kalan uygulama mobil listede yok")
        XCTAssertEqual(mobile.first?.down, 1_000)
        XCTAssertEqual(mobile.first?.up, 10)
        let wifi = h.rows(range: .min15, interface: .wifi, nowMinute: m0)
        XCTAssertEqual(wifi.first { $0.app == chrome }?.bytes, 3_030)
        XCTAssertEqual(h.rows(range: .min15, interface: .all, nowMinute: m0).first?.bytes, 4_040)
    }

    func testNowRangeShowsPerSecondValuesSortedByCurrentRate() {
        var h = LiveUsageHistory()
        let safari = "/Applications/Safari.app"
        h.advance(seconds: 1)
        h.record(app: chrome, bytesIn: 50_000, bytesOut: 0, mobile: true, minute: m0)   // eski: anlık pencereden düşecek
        h.advance(seconds: LiveUsageHistory.rateWindow)
        h.record(app: safari, bytesIn: 10_000, bytesOut: 5_000, mobile: true, minute: m0)
        let rows = h.rows(range: .now, interface: .all, nowMinute: m0)
        XCTAssertEqual(rows.map(\.app), [safari], "anlıkta yalnızca son saniyelerde trafiği olanlar")
        XCTAssertEqual(rows.first?.down, 2_000)   // 10_000 / 5 sn
        XCTAssertEqual(rows.first?.up, 1_000)
        XCTAssertEqual(rows.first?.bytes, 3_000)  // B/s
        XCTAssertEqual(h.rows(range: .sec60, interface: .all, nowMinute: m0).first?.app, chrome, "60 sn toplamında eski trafik önde")
    }

    func testRateIsAverageOfLastFiveSeconds() {
        var h = LiveUsageHistory()
        h.advance(seconds: 1)
        h.record(app: chrome, bytesIn: 10_000, bytesOut: 0, mobile: true, minute: m0)
        XCTAssertEqual(h.rows(range: .sec60, interface: .all, nowMinute: m0).first?.rate, 2_000)
        h.advance(seconds: LiveUsageHistory.rateWindow)
        let row = h.rows(range: .sec60, interface: .all, nowMinute: m0).first
        XCTAssertEqual(row?.rate, 0, "eski trafik anlık hızı etkilemez")
        XCTAssertEqual(row?.bytes, 10_000, "ama 60 sn toplamında kalır")
    }

    @MainActor
    func testEngineFeedsLiveRowsWithoutProxyEgress() {
        let engine = UsageEngine(store: UsageStore())
        let now = Date.now
        let minute = Int(now.timeIntervalSince1970 / 60)
        engine.ingest([
            UsageBucket(app: chrome, signingID: "", host: "x.googlevideo.com", kind: .proxied, expensive: true,
                        minute: minute, bytesIn: 4_000, bytesOut: 100),
            UsageBucket(app: "/Users/u/spoofdpi", signingID: "", host: "1.2.3.4", kind: .proxyEgress, expensive: true,
                        minute: minute, bytesIn: 4_000, bytesOut: 100),
        ], now: now)
        for range in LiveRange.allCases where range != .now {
            let rows = engine.liveRows(range: range, interface: .mobile, now: now)
            XCTAssertEqual(rows.map(\.app), [chrome], "\(range.title)")
            XCTAssertEqual(rows.first?.bytes, 4_100)
        }
        XCTAssertTrue(engine.liveRows(range: .min5, interface: .wifi, now: now).isEmpty)
    }

    func testRangeTitles() {
        XCTAssertEqual(LiveRange.allCases.map(\.title), ["Anlık", "60 sn", "5 dk", "15 dk", "30 dk", "1 sa"])
        XCTAssertEqual(LiveInterface.allCases.map(\.title), ["Tümü", "Wi‑Fi", "Mobil"])
    }

    // MARK: Komut → kural eşlemesi (sahte kontroller)

    @MainActor
    private final class FakeControls {
        var limits: [String: AppLimit] = [:]
        var blocked: [String: BlockScope] = [:]
        var calls: [String] = []
        var onMobile = false

        var controls: LiveAppControls {
            LiveAppControls(
                limit: { self.limits[$0] },
                blockScope: { self.blocked[$0] },
                setLimit: { app, l in self.calls.append("setLimit"); self.limits[app] = l },
                setBlockScope: { app, s in self.calls.append("setBlock:\(s?.rawValue ?? "nil")"); self.blocked[app] = s },
                isMobile: { self.onMobile }
            )
        }
    }

    @MainActor
    func testLimitPresetAppliesBothDirectionsWithPageScopeAndUndoRestores() throws {
        let fake = FakeControls()
        let record = try XCTUnwrap(LiveAppActionMapper.apply(.limit(bytesPerSec: 100 * 1024), app: chrome, onlyOnMobile: true, controls: fake.controls))
        XCTAssertEqual(fake.limits[chrome], AppLimit(downBytesPerSec: 102_400, upBytesPerSec: 102_400, onlyOnMobile: true))
        XCTAssertNil(record.previousLimit)
        XCTAssertTrue(record.message.contains("100 KB/s"))
        LiveAppActionMapper.undo(record, controls: fake.controls)
        XCTAssertNil(fake.limits[chrome])
        XCTAssertEqual(fake.calls, ["setLimit", "setLimit"])
    }

    @MainActor
    func testNetworkPageLimitIsAllNetworksAndReplacingKeepsPreviousForUndo() throws {
        let fake = FakeControls()
        let old = AppLimit(downBytesPerSec: 5 * 1024 * 1024)
        fake.limits[chrome] = old
        let record = try XCTUnwrap(LiveAppActionMapper.apply(.limit(bytesPerSec: 1024 * 1024), app: chrome, onlyOnMobile: false, controls: fake.controls))
        XCTAssertEqual(fake.limits[chrome], AppLimit(downBytesPerSec: 1_048_576, upBytesPerSec: 1_048_576, onlyOnMobile: false))
        LiveAppActionMapper.undo(record, controls: fake.controls)
        XCTAssertEqual(fake.limits[chrome], old)
    }

    @MainActor
    func testNoOpCommandsDoNotTouchControls() {
        let fake = FakeControls()
        XCTAssertNil(LiveAppActionMapper.apply(.clearLimit, app: chrome, onlyOnMobile: false, controls: fake.controls))
        XCTAssertNil(LiveAppActionMapper.apply(.unblock, app: chrome, onlyOnMobile: false, controls: fake.controls))
        XCTAssertNil(LiveAppActionMapper.apply(.limit(bytesPerSec: 10), app: chrome, onlyOnMobile: false, controls: fake.controls),
                     "1 KB/s altı geçersiz")
        fake.limits[chrome] = AppLimit(downBytesPerSec: 102_400, upBytesPerSec: 102_400, onlyOnMobile: true)
        XCTAssertNil(LiveAppActionMapper.apply(.limit(bytesPerSec: 102_400), app: chrome, onlyOnMobile: true, controls: fake.controls),
                     "aynı sınır tekrar uygulanmaz")
        XCTAssertTrue(fake.calls.isEmpty)
    }

    @MainActor
    func testBlockUnblockAndClearLimitMapToExistingAPIs() throws {
        let fake = FakeControls()
        let block = try XCTUnwrap(LiveAppActionMapper.apply(.block(.mobile), app: slack, onlyOnMobile: true, controls: fake.controls))
        XCTAssertEqual(fake.blocked[slack], .mobile)
        XCTAssertNil(block.previousBlock)
        LiveAppActionMapper.undo(block, controls: fake.controls)
        XCTAssertNil(fake.blocked[slack])

        fake.blocked[slack] = .mobile
        fake.limits[slack] = AppLimit(downBytesPerSec: 2048)
        XCTAssertNotNil(LiveAppActionMapper.apply(.unblock, app: slack, onlyOnMobile: true, controls: fake.controls))
        XCTAssertNotNil(LiveAppActionMapper.apply(.clearLimit, app: slack, onlyOnMobile: true, controls: fake.controls))
        XCTAssertNil(fake.blocked[slack])
        XCTAssertNil(fake.limits[slack])
        XCTAssertEqual(fake.calls, ["setBlock:mobile", "setBlock:nil", "setBlock:nil", "setLimit"])
    }

    @MainActor
    func testSystemProcessAndEverywhereBlockNeedConfirmation() {
        XCTAssertTrue(LiveAppActionMapper.needsConfirmation(.block(.mobile), app: mds))
        XCTAssertTrue(LiveAppActionMapper.needsConfirmation(.block(.mobile), app: "/usr/libexec/nsurlsessiond"))
        XCTAssertFalse(LiveAppActionMapper.needsConfirmation(.block(.mobile), app: chrome))
        XCTAssertFalse(LiveAppActionMapper.needsConfirmation(.block(.wifi), app: chrome))
        XCTAssertTrue(LiveAppActionMapper.needsConfirmation(.block(.everywhere), app: chrome), "her yerde engel her uygulamada onay ister")
        XCTAssertFalse(LiveAppActionMapper.needsConfirmation(.unblock, app: mds))
        XCTAssertFalse(LiveAppActionMapper.needsConfirmation(.limit(bytesPerSec: 102_400), app: mds))
    }

    func testCustomValueParsingAndBadges() {
        XCTAssertEqual(LiveAppActionMapper.customBytesPerSec(kilobytesText: " 250 "), 256_000)
        XCTAssertNil(LiveAppActionMapper.customBytesPerSec(kilobytesText: "0"))
        XCTAssertNil(LiveAppActionMapper.customBytesPerSec(kilobytesText: "abc"))
        XCTAssertTrue(LiveAppActionMapper.badges(limit: nil, block: nil).isEmpty)
        let badges = LiveAppActionMapper.badges(limit: AppLimit(downBytesPerSec: 1_048_576, upBytesPerSec: 102_400, onlyOnMobile: true), block: .mobile)
        XCTAssertEqual(badges, [LiveAppBadge(text: "Mobilde engelli", isBlock: true), LiveAppBadge(text: "≤ 100 KB/s mobilde", isBlock: false)])
        XCTAssertEqual(LiveAppActionMapper.badges(limit: nil, block: .wifi), [LiveAppBadge(text: "Wi-Fi'de engelli", isBlock: true)])
        XCTAssertEqual(LiveAppActionMapper.badges(limit: nil, block: .everywhere), [LiveAppBadge(text: "Her yerde engelli", isBlock: true)])
    }

    // MARK: Engel kapsamı (Mobilde / Wi-Fi'de / Her yerde)

    @MainActor
    func testEachBlockScopeMapsToControlsAndUndoRestoresPreviousScope() throws {
        let fake = FakeControls()
        for scope in BlockScope.allCases {
            let record = try XCTUnwrap(LiveAppActionMapper.apply(.block(scope), app: chrome, onlyOnMobile: false, controls: fake.controls))
            XCTAssertEqual(fake.blocked[chrome], scope)
            XCTAssertNil(record.previousBlock)
            LiveAppActionMapper.undo(record, controls: fake.controls)
            XCTAssertNil(fake.blocked[chrome], "geri al engeli kaldırır (\(scope))")
        }
        XCTAssertEqual(fake.calls, ["setBlock:mobile", "setBlock:nil", "setBlock:wifi", "setBlock:nil", "setBlock:everywhere", "setBlock:nil"])
    }

    @MainActor
    func testChangingScopeKeepsPreviousScopeForUndoAndSameScopeIsNoOp() throws {
        let fake = FakeControls()
        fake.blocked[chrome] = .mobile
        XCTAssertNil(LiveAppActionMapper.apply(.block(.mobile), app: chrome, onlyOnMobile: true, controls: fake.controls))
        let record = try XCTUnwrap(LiveAppActionMapper.apply(.block(.everywhere), app: chrome, onlyOnMobile: true, controls: fake.controls))
        XCTAssertEqual(fake.blocked[chrome], .everywhere)
        XCTAssertEqual(record.previousBlock, .mobile)
        LiveAppActionMapper.undo(record, controls: fake.controls)
        XCTAssertEqual(fake.blocked[chrome], .mobile)

        let unblock = try XCTUnwrap(LiveAppActionMapper.apply(.unblock, app: chrome, onlyOnMobile: true, controls: fake.controls))
        XCTAssertNil(fake.blocked[chrome])
        LiveAppActionMapper.undo(unblock, controls: fake.controls)
        XCTAssertEqual(fake.blocked[chrome], .mobile, "engeli kaldırmayı geri al eski kapsamı geri getirir")
    }

    @MainActor
    func testSystemDaemonCanOnlyBeBlockedOnMobile() {
        let all: [BlockScope] = [.mobile, .wifi, .everywhere]
        XCTAssertEqual(LiveAppActionMapper.allowedScopes(app: chrome), all)
        XCTAssertEqual(LiveAppActionMapper.allowedScopes(app: "/System/Applications/Utilities/Terminal.app"), all, "Terminal her yerde engellenebilir")
        XCTAssertEqual(LiveAppActionMapper.allowedScopes(app: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"), all)
        XCTAssertEqual(LiveAppActionMapper.allowedScopes(app: "/usr/sbin/mDNSResponder"), [.mobile])
        XCTAssertEqual(LiveAppActionMapper.allowedScopes(app: "/usr/libexec/trustd"), [.mobile])
        let fake = FakeControls()
        XCTAssertNil(LiveAppActionMapper.apply(.block(.wifi), app: "/usr/sbin/mDNSResponder", onlyOnMobile: false, controls: fake.controls))
        XCTAssertNil(LiveAppActionMapper.apply(.block(.everywhere), app: mds, onlyOnMobile: false, controls: fake.controls))
        XCTAssertNotNil(LiveAppActionMapper.apply(.block(.mobile), app: mds, onlyOnMobile: false, controls: fake.controls))
        XCTAssertEqual(fake.calls, ["setBlock:mobile"])
    }

    @MainActor
    func testBlockMessageNotesWhenScopeDoesNotAffectCurrentNetwork() throws {
        let fake = FakeControls()
        fake.onMobile = true
        let wifi = try XCTUnwrap(LiveAppActionMapper.apply(.block(.wifi), app: chrome, onlyOnMobile: false, controls: fake.controls))
        XCTAssertTrue(wifi.message.contains("Wi-Fi/kablolu ağda engellendi"), wifi.message)
        XCTAssertTrue(wifi.message.contains("şu an mobil veridesin"), wifi.message)
        let all = try XCTUnwrap(LiveAppActionMapper.apply(.block(.everywhere), app: slack, onlyOnMobile: false, controls: fake.controls))
        XCTAssertFalse(all.message.contains("etkilenmez"), all.message)
        let confirm = LiveAppActionMapper.confirmation(scope: .everywhere, app: slack)
        XCTAssertTrue(confirm.message.contains("hiçbir ağda"), confirm.message)
        XCTAssertTrue(confirm.message.contains("internete çıkamayacak"), confirm.message)
    }

    @MainActor
    func testPreferencesStoreScopesInMobileAndWiFiLists() throws {
        let suite = "adalmon.test.blockscope.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let p = Preferences(defaults: d)
        p.setBlockScope(chrome, .everywhere)
        XCTAssertEqual(p.blockedOnMobile, [chrome])
        XCTAssertEqual(p.blockedOnWiFi, [chrome])
        p.setBlockScope(chrome, .wifi)
        XCTAssertEqual(p.blockScope(for: chrome), .wifi)
        XCTAssertTrue(p.blockedOnMobile.isEmpty)
        p.setBlockScope(chrome, .mobile)
        XCTAssertEqual(Preferences(defaults: d).blockScope(for: chrome), .mobile, "kalıcı")
        p.setBlockScope(chrome, nil)
        XCTAssertNil(Preferences(defaults: d).blockScope(for: chrome))
    }
}
