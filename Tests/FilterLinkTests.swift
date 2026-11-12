import XCTest
@testable import Adalmon

/// Uygulama ↔ filtre bağlantısı: geri çekilme, yeniden bağlanınca yapılandırmanın yeniden gönderilmesi, uyarı koşulları,
/// Wi-Fi kapsamlı engellerin listelerde görünmesi. Gerçek XPC/filtre yok (sahte taşıma).
@MainActor
final class FilterLinkTests: XCTestCase {
    /// Sahte taşıma: kapalıyken ilk çağrıda "yeni bağlantı" kurar (generation artar), `reset` bağlantıyı bırakır.
    final class FakeTransport: FilterTransport {
        var generation = 0
        var reachable = true
        var drains = 0
        var sent: [FilterConfig] = []
        private var open = false

        func drain() async -> [UsageBucket]? {
            drains += 1
            ensureOpen()
            return reachable ? [] : nil
        }

        func send(_ config: Data) {
            ensureOpen()
            if let cfg = try? JSONDecoder().decode(FilterConfig.self, from: config) { sent.append(cfg) }
        }

        func reset() { open = false }

        private func ensureOpen() {
            if !open { open = true; generation += 1 }
        }
    }

    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func makeClient(_ t: FakeTransport) -> FilterClient {
        FilterClient(transport: t, now: { [unowned self] in self.clock })
    }

    private func advance(_ s: TimeInterval) { clock = clock.addingTimeInterval(s) }

    private func config(_ blocked: [String]) -> FilterConfig {
        var c = FilterConfig()
        c.blockedOnMobile = blocked
        return c
    }

    // MARK: Geri çekilme

    func testBackoffSchedule() {
        XCTAssertEqual((1...7).map { FilterBackoff.delay(afterFailures: $0) }, [2, 4, 8, 16, 30, 30, 30])
        XCTAssertEqual(FilterBackoff.delay(afterFailures: 1000), 30)
    }

    func testBackoffLogsFirstAndEveryNth() {
        var b = FilterBackoff()
        let logged = (1...20).map { _ in b.recordFailure(now: clock) }
        XCTAssertEqual(logged.enumerated().filter(\.element).map { $0.offset + 1 }, [1, 10, 20])
    }

    func testDrainWaitsForBackoffInsteadOfEveryStep() async {
        let t = FakeTransport()
        t.reachable = false
        let client = makeClient(t)
        _ = await client.drain()                      // 1. hata → 2 sn
        XCTAssertEqual(t.drains, 1)
        advance(1); _ = await client.drain()
        XCTAssertEqual(t.drains, 1, "bekleme süresi dolmadan denenmez")
        advance(1); _ = await client.drain()          // 2. hata → 4 sn
        XCTAssertEqual(t.drains, 2)
        advance(3); _ = await client.drain()
        XCTAssertEqual(t.drains, 2)
        advance(1); _ = await client.drain()          // 3. hata → 8 sn
        XCTAssertEqual(t.drains, 3)
        XCTAssertFalse(client.isConnected)
        XCTAssertEqual(client.disconnectedSince, Date(timeIntervalSince1970: 1_000_000))
    }

    func testReconnectNowSkipsWait() async {
        let t = FakeTransport()
        t.reachable = false
        let client = makeClient(t)
        _ = await client.drain()
        _ = await client.drain()
        XCTAssertEqual(t.drains, 1)
        client.reconnectNow()
        t.reachable = true
        _ = await client.drain()
        XCTAssertEqual(t.drains, 2)
        XCTAssertTrue(client.isConnected)
        XCTAssertNil(client.disconnectedSince)
    }

    // MARK: Yapılandırmanın yeniden gönderilmesi

    func testConfigResentOnReconnect() async {
        let t = FakeTransport()
        let client = makeClient(t)
        client.send(config(["a"]))
        _ = await client.drain()
        XCTAssertEqual(t.sent.map(\.blockedOnMobile), [["a"]], "aynı bağlantıda tekrar gönderilmez")

        // Uzantı değişti: bağlantı kopar.
        t.reachable = false
        t.reset()
        _ = await client.drain()
        XCTAssertFalse(client.isConnected)
        client.send(config(["a", "b"]))               // koparken bağlantı açılmaz, saklanır
        XCTAssertEqual(t.sent.count, 1)

        t.reachable = true
        advance(2)
        _ = await client.drain()
        XCTAssertTrue(client.isConnected)
        XCTAssertEqual(t.sent.map(\.blockedOnMobile), [["a"], ["a", "b"]], "yeni bağlantıya son yapılandırma hemen gider")
        _ = await client.drain()
        XCTAssertEqual(t.sent.count, 2)
    }

    func testInterruptedConnectionWithinOneStepStillResends() async {
        let t = FakeTransport()
        let client = makeClient(t)
        client.send(config(["a"]))
        _ = await client.drain()
        t.reset()                                     // kopma ve yeniden bağlanma iki adım arasında oldu
        _ = await client.drain()
        XCTAssertEqual(t.sent.count, 2)
    }

    func testNothingSentBeforeAppProvidesConfig() async {
        let t = FakeTransport()
        let client = makeClient(t)
        _ = await client.drain()
        t.reset()
        _ = await client.drain()
        XCTAssertTrue(t.sent.isEmpty)
    }

    // MARK: Durum ve uyarı

    func testLinkState() {
        XCTAssertEqual(FilterLinkState.make(installer: .active, connected: true, disconnectedSince: nil, now: clock), .connected)
        XCTAssertEqual(FilterLinkState.make(installer: .active, connected: false, disconnectedSince: clock, now: clock.addingTimeInterval(9)),
                       .reconnecting(since: clock))
        XCTAssertEqual(FilterLinkState.make(installer: .notInstalled, connected: true, disconnectedSince: nil, now: clock), .inactive)
        XCTAssertEqual(FilterLinkState.make(installer: .needsApproval, connected: false, disconnectedSince: nil, now: clock), .inactive)
        XCTAssertEqual(FilterLinkState.make(installer: .unknown, connected: true, disconnectedSince: nil, now: clock), .checking)
    }

    func testMobileWarningAfterSixtySecondsThenEveryThirtyMinutes() {
        var w = FilterLinkWatch()
        XCTAssertEqual(w.update(connected: false, isMobile: true, now: clock).level, .none)
        let at59 = w.update(connected: false, isMobile: true, now: clock.addingTimeInterval(59))
        XCTAssertEqual(at59.level, .none)
        XCTAssertFalse(at59.alert)
        let at61 = w.update(connected: false, isMobile: true, now: clock.addingTimeInterval(61))
        XCTAssertEqual(at61.level, .critical)
        XCTAssertTrue(at61.alert)
        let later = w.update(connected: false, isMobile: true, now: clock.addingTimeInterval(61 + 29 * 60))
        XCTAssertEqual(later.level, .critical)
        XCTAssertFalse(later.alert, "30 dk dolmadan tekrar yok")
        XCTAssertTrue(w.update(connected: false, isMobile: true, now: clock.addingTimeInterval(61 + 30 * 60)).alert)
    }

    func testWiFiShowsNoteWithoutAlert() {
        var w = FilterLinkWatch()
        _ = w.update(connected: false, isMobile: false, now: clock)
        let r = w.update(connected: false, isMobile: false, now: clock.addingTimeInterval(120))
        XCTAssertEqual(r.level, .note)
        XCTAssertFalse(r.alert)
        // Wi-Fi'de geçen süre de sayılır: mobile geçince hemen uyarı.
        XCTAssertTrue(w.update(connected: false, isMobile: true, now: clock.addingTimeInterval(121)).alert)
    }

    func testReconnectClearsWarningAndNextOutageAlertsAgain() {
        var w = FilterLinkWatch()
        _ = w.update(connected: false, isMobile: true, now: clock)
        XCTAssertTrue(w.update(connected: false, isMobile: true, now: clock.addingTimeInterval(61)).alert)
        XCTAssertEqual(w.update(connected: true, isMobile: true, now: clock.addingTimeInterval(70)).level, .none)
        _ = w.update(connected: false, isMobile: true, now: clock.addingTimeInterval(80))
        XCTAssertFalse(w.update(connected: false, isMobile: true, now: clock.addingTimeInterval(130)).alert, "yeni kopuşta da 60 sn tolerans")
        XCTAssertTrue(w.update(connected: false, isMobile: true, now: clock.addingTimeInterval(141)).alert)
    }

    func testFilterDownAlertRespectsDeliveryChoice() async {
        let notifier = AlertDeliveryTests.FakeNotifier(current: .authorized)
        let center = AlertCenter(notifier: notifier)
        center.delivery = { .inApp }
        var shown: [AlertMessage] = []
        center.presentInApp = { message, _ in shown.append(message) }
        await center.refreshPermission()
        center.notifyFilterDown()
        XCTAssertEqual(shown.map(\.id), ["filter-down"])
        XCTAssertTrue(notifier.posted.isEmpty)

        center.delivery = { .system }
        center.notifyFilterDown()
        XCTAssertEqual(notifier.posted.map(\.id), ["filter-down"])
        XCTAssertTrue(notifier.posted[0].body.contains("UYGULANMIYOR"))
    }

    // MARK: Wi-Fi kapsamlı engeller listelerde

    func testBlockedListIncludesWiFiScope() {
        let list = BlockedAppEntry.list(mobile: ["a", "b"], wifi: ["b", "c", "c"])
        XCTAssertEqual(list, [BlockedAppEntry(app: "a", scope: .mobile), BlockedAppEntry(app: "b", scope: .everywhere),
                              BlockedAppEntry(app: "c", scope: .wifi)])
        XCTAssertFalse(list[2].isActive(onMobile: true))
        XCTAssertTrue(list[2].isActive(onMobile: false))

        var data = PanelData.sample
        data.blockedApps = []
        data.blockedOnWiFi = ["c"]
        XCTAssertEqual(data.blockedEntries.map(\.scope), [.wifi], "yalnızca Wi-Fi'de engelli uygulama da listede")
    }
}
