import XCTest
@testable import Adalmon

final class UsageLogicTests: XCTestCase {
    func testDomainGrouping() {
        XCTAssertEqual(DomainGrouper.group("rr3---sn-u0g3jxaa-n5fk.googlevideo.com"), "YouTube")
        XCTAssertEqual(DomainGrouper.group("i.ytimg.com"), "YouTube")
        XCTAssertEqual(DomainGrouper.group("api.anthropic.com"), "Claude")
        XCTAssertEqual(DomainGrouper.group("cdn.example.com.tr"), "example.com.tr")
        XCTAssertEqual(DomainGrouper.group("a.b.example.org"), "example.org")
        XCTAssertEqual(DomainGrouper.group("160.79.104.10"), "160.79.104.10")
        XCTAssertEqual(DomainGrouper.group(""), "Bilinmeyen")
    }

    @MainActor
    func testProxyEgressIsNotAttributed() {
        let engine = UsageEngine(store: UsageStore())
        let minute = Int(Date.now.timeIntervalSince1970 / 60)
        engine.ingest([
            UsageBucket(app: "/Applications/Google Chrome.app", signingID: "com.google.Chrome.helper", host: "x.googlevideo.com",
                        kind: .proxied, expensive: true, minute: minute, bytesIn: 40_000_000, bytesOut: 1_000),
            UsageBucket(app: "/Users/u/Desktop/spoofdpi", signingID: "", host: "1.2.3.4",
                        kind: .proxyEgress, expensive: true, minute: minute, bytesIn: 40_000_000, bytesOut: 1_000),
        ])
        XCTAssertEqual(engine.last60.count, 1)
        XCTAssertEqual(engine.last60.first?.app, "/Applications/Google Chrome.app")
        XCTAssertEqual(engine.last60.first?.domains.first?.name, "YouTube")
        XCTAssertEqual(engine.attributedMobileToday, 40_001_000)
        XCTAssertEqual(engine.proxyEgressToday, 40_001_000)
    }

    // MARK: Proxy (SpoofDPI) mobil düzeltmesi: loopback mobil sayılmaz, mobil payı egress belirler.

    private static let mb: UInt64 = 1_000_000
    private static let minute = Int(Date.now.timeIntervalSince1970 / 60)

    private static func bucket(_ app: String, _ kind: FlowKind, _ bytes: UInt64, expensive: Bool = true,
                               host: String = "x.example.com", out: UInt64 = 0) -> UsageBucket {
        UsageBucket(app: app, signingID: "", host: host, kind: kind, expensive: expensive, minute: minute,
                    bytesIn: bytes - out, bytesOut: out)
    }

    @MainActor private func mobile(_ engine: UsageEngine, _ app: String) -> UInt64? {
        engine.today.first { $0.app == app }?.mobileBytes
    }

    @MainActor
    func testProxiedMobileEqualsEgressNotDoubled() {
        let engine = UsageEngine(store: UsageStore())
        engine.ingest([Self.bucket("/py", .proxied, 100 * Self.mb, out: 2 * Self.mb),
                       Self.bucket("/spoofdpi", .proxyEgress, 100 * Self.mb)])
        XCTAssertEqual(mobile(engine, "/py"), 100 * Self.mb)
        XCTAssertEqual(engine.attributedMobileToday, 100 * Self.mb)
        XCTAssertEqual(engine.last60.first?.mobileBytes, 100 * Self.mb)
        XCTAssertNil(mobile(engine, "/spoofdpi"))
        let live = engine.liveRows(range: .sec60, interface: .mobile)
        XCTAssertEqual(live.first.map { $0.down + $0.up }, 100 * Self.mb)
    }

    @MainActor
    func testProxiedWithoutEgressIsNotMobile() {
        let engine = UsageEngine(store: UsageStore())
        engine.ingest([Self.bucket("/py", .proxied, 465 * Self.mb)])
        XCTAssertEqual(mobile(engine, "/py"), 0)
        XCTAssertEqual(engine.today.first?.bytes, 465 * Self.mb, "toplamda görünmeye devam eder")
        XCTAssertEqual(engine.attributedMobileToday, 0)
        XCTAssertEqual(engine.last60.first?.mobileBytes, 0)
        XCTAssertTrue(engine.liveRows(range: .hour1, interface: .mobile).isEmpty)
        XCTAssertEqual(engine.liveRows(range: .hour1, interface: .wifi).first?.down, 465 * Self.mb)
        // Wi-Fi'deki egress de mobil değildir.
        engine.ingest([Self.bucket("/py", .proxied, 10 * Self.mb), Self.bucket("/spoofdpi", .proxyEgress, 10 * Self.mb, expensive: false)])
        XCTAssertEqual(engine.attributedMobileToday, 0)
    }

    @MainActor
    func testEgressSplitsProportionallyAcrossProxiedApps() {
        let engine = UsageEngine(store: UsageStore())
        engine.ingest([Self.bucket("/a", .proxied, 200 * Self.mb), Self.bucket("/b", .proxied, 100 * Self.mb),
                       Self.bucket("/spoofdpi", .proxyEgress, 100 * Self.mb)])
        let a = mobile(engine, "/a") ?? 0, b = mobile(engine, "/b") ?? 0
        XCTAssertEqual(a + b, 100 * Self.mb)
        XCTAssertEqual(Double(a), 66_666_667, accuracy: 1)
        XCTAssertEqual(Double(b), 33_333_333, accuracy: 1)
        XCTAssertEqual(engine.today.first { $0.app == "/a" }?.bytes, 200 * Self.mb)
    }

    @MainActor
    func testInterfaceCapClampsMobileAttribution() {
        let engine = UsageEngine(store: UsageStore())
        engine.ingest([Self.bucket("/a", .direct, 60 * Self.mb), Self.bucket("/b", .direct, 40 * Self.mb)],
                      mobileCap: 50 * Self.mb)
        XCTAssertEqual(engine.attributedMobileToday, 50 * Self.mb)
        XCTAssertEqual(mobile(engine, "/a"), 30 * Self.mb)
        XCTAssertEqual(mobile(engine, "/b"), 20 * Self.mb)
        XCTAssertEqual(engine.droppedMobileExcess, 50 * Self.mb)
        XCTAssertEqual(engine.today.first?.bytes, 60 * Self.mb, "toplam değişmez")
        // Sınırın altında dokunulmaz.
        engine.ingest([Self.bucket("/a", .direct, 10 * Self.mb)], mobileCap: 20 * Self.mb)
        XCTAssertEqual(mobile(engine, "/a"), 40 * Self.mb)
        XCTAssertEqual(engine.droppedMobileExcess, 50 * Self.mb)
    }

    @MainActor
    func testDirectFlowsUnchanged() {
        let engine = UsageEngine(store: UsageStore())
        engine.ingest([Self.bucket("/a", .direct, 30 * Self.mb, out: 5 * Self.mb),
                       Self.bucket("/b", .direct, 20 * Self.mb, expensive: false)])
        XCTAssertEqual(mobile(engine, "/a"), 30 * Self.mb)
        XCTAssertEqual(mobile(engine, "/b"), 0)
        XCTAssertEqual(engine.attributedMobileToday, 30 * Self.mb)
        let live = engine.liveRows(range: .sec60, interface: .mobile)
        XCTAssertEqual(live.map(\.app), ["/a"])
        XCTAssertEqual(live.first?.down, 25 * Self.mb)
        XCTAssertEqual(live.first?.up, 5 * Self.mb)
    }

    func testMobileSharesSplitsDirectionAndKeepsTotals() {
        let shares = UsageEngine.mobileShares([Self.bucket("/a", .proxied, 90),
                                               Self.bucket("/s", .proxyEgress, 30),
                                               Self.bucket("/b", .direct, 7, expensive: false)], cap: nil)
        XCTAssertEqual(shares.bytes, [30, 0, 0])
        XCTAssertEqual(shares.dropped, 0)
        XCTAssertEqual(UsageEngine.distribute(10, weights: [1, 1, 1]).reduce(0, +), 10)
        XCTAssertEqual(UsageEngine.distribute(0, weights: [5]), [0])
    }
}
