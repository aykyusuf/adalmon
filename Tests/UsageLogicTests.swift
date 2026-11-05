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
}
