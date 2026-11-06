import XCTest
@testable import Adalmon

final class DomainGrouperTests: XCTestCase {
    func testLocalAddressesCollapseIntoLocalNetwork() {
        for h in ["192.168.1.148", "10.1.2.3", "172.20.0.9", "169.254.1.1", "fe80::ec:fd1e:f9c4:435c%en0", "fe80::1",
                  "fd00::5", "fc00::1", "macbook.local", "printer.LOCAL", "router.lan", "224.0.0.251", "ff02::fb"] {
            XCTAssertEqual(DomainGrouper.group(h), DomainGrouper.localName, h)
        }
    }

    func testLoopbackIsAttributedToProxy() {
        for h in ["127.0.0.1", "127.0.0.2", "::1", "localhost", "[::1]"] {
            XCTAssertEqual(DomainGrouper.group(h), "SpoofDPI üzerinden", h)
        }
    }

    func testPublicIPsStayRaw() {
        XCTAssertEqual(DomainGrouper.group("160.79.104.10"), "160.79.104.10")
        XCTAssertEqual(DomainGrouper.group("172.32.0.1"), "172.32.0.1")
        XCTAssertEqual(DomainGrouper.group("2001:4860:4860::8888"), "2001:4860:4860::8888")
        XCTAssertEqual(DomainGrouper.group("::ffff:8.8.8.8"), "8.8.8.8")
    }

    func testBrandGrouping() {
        let cases: [(String, String)] = [
            ("rr3---sn-u0g3jxaa-n5fk.googlevideo.com", "YouTube"), ("youtubei.googleapis.com", "YouTube"),
            ("storage.googleapis.com", "Google"), ("www.google.com.tr", "Google"), ("fonts.gstatic.com", "Google"),
            ("updates.cdn-apple.com", "Apple"), ("aod.itunes.apple.com", "Apple"), ("is1-ssl.mzstatic.com", "Apple"),
            ("gateway.icloud.com", "iCloud"), ("edge-116.defra2.icloud-content.com", "iCloud"),
            ("api.github.com", "GitHub"), ("release-assets.githubusercontent.com", "GitHub"),
            ("speed.cloudflare.com", "Cloudflare"), ("api.anthropic.com", "Claude"), ("downloads.claude.ai", "Claude"),
            ("audio-fa.scdn.co", "Spotify"), ("occ-0-1.nflxvideo.net", "Netflix"),
            ("media-ist1-1.cdn.whatsapp.net", "WhatsApp"), ("scontent.cdninstagram.com", "Instagram"), ("static.xx.fbcdn.net", "Facebook"),
            ("web.telegram.org", "Telegram"), ("gateway.discord.gg", "Discord"),
            ("login.microsoftonline.com", "Microsoft"), ("dms.licdn.com", "LinkedIn"), ("video.twimg.com", "X"),
            ("s3.eu-west-1.amazonaws.com", "Amazon AWS"), ("www.amazon.com.tr", "Amazon"),
            ("e1234.dscb.akamaiedge.net", "Akamai (CDN)"), ("d111.cloudfront.net", "CloudFront (CDN)"),
            ("vod-akc-eu-west-2.media.dssott.com", "Disney+"), ("http-intake.logs.us5.datadoghq.com", "Datadog"),
        ]
        for (host, expected) in cases { XCTAssertEqual(DomainGrouper.group(host), expected, host) }
    }

    func testUnknownDomainsReduceToRegistrableDomain() {
        XCTAssertEqual(DomainGrouper.group("cdn.example.com.tr"), "example.com.tr")
        XCTAssertEqual(DomainGrouper.group("a.b.example.org"), "example.org")
        XCTAssertEqual(DomainGrouper.group("WWW.Example.ORG."), "example.org")
        XCTAssertEqual(DomainGrouper.group("kuveytturkyatirim.com.tr"), "kuveytturkyatirim.com.tr")
        XCTAssertEqual(DomainGrouper.group("iett.istanbul"), "iett.istanbul")
        XCTAssertEqual(DomainGrouper.group(""), "Bilinmeyen")
        XCTAssertEqual(DomainGrouper.group("?"), "Bilinmeyen")
    }

    func testGroupIsIdempotent() {
        let hosts = ["x.googlevideo.com", "192.168.1.1", "127.0.0.1", "8.8.8.8", "a.example.org", "", "e.akamaiedge.net",
                     "fe80::1%en0", "s3.amazonaws.com", "host.local"]
        for h in hosts {
            let once = DomainGrouper.group(h)
            XCTAssertEqual(DomainGrouper.group(once), once, h)
        }
    }

    func testCategories() {
        XCTAssertEqual(DomainGrouper.category(ofGroup: "YouTube"), .named)
        XCTAssertEqual(DomainGrouper.category(ofGroup: "example.org"), .named)
        XCTAssertEqual(DomainGrouper.category(ofGroup: "SpoofDPI üzerinden"), .viaProxy)
        XCTAssertEqual(DomainGrouper.category(ofGroup: "160.79.104.10"), .address)
        XCTAssertEqual(DomainGrouper.category(ofGroup: "Bilinmeyen"), .address)
        XCTAssertEqual(DomainGrouper.category(ofGroup: "Yerel ağ"), .local)
    }

    func testDisplayOrderPutsNamedFirstAndLocalLast() {
        let items: [(name: String, bytes: UInt64)] = [
            ("Yerel ağ", 900), ("160.79.104.10", 800), ("SpoofDPI üzerinden", 700), ("github.com", 50), ("YouTube", 100),
        ]
        let ordered = DomainGrouper.displayOrder(items, limit: 5, name: \.name, bytes: \.bytes)
        XCTAssertEqual(ordered.map(\.name), ["YouTube", "github.com", "SpoofDPI üzerinden", "160.79.104.10", "Yerel ağ"])
    }

    func testDisplayOrderLimitKeepsBiggestThenReorders() {
        let items: [(name: String, bytes: UInt64)] = [("Yerel ağ", 900), ("b.com", 10), ("a.com", 500), ("c.com", 1)]
        let ordered = DomainGrouper.displayOrder(items, limit: 3, name: \.name, bytes: \.bytes)
        XCTAssertEqual(ordered.map(\.name), ["a.com", "b.com", "Yerel ağ"])
    }

    func testStoreTopDomainsAggregatesLocalAndOrdersLast() async {
        let path = NSTemporaryDirectory() + "dg-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let s = UsageStore(path: path)
        await s.add(day: "2027-02-01", rows: [
            .init(app: "A", host: "192.168.1.148", mobile: false, bytesIn: 1000, bytesOut: 0),
            .init(app: "A", host: "fe80::1%en0", mobile: false, bytesIn: 500, bytesOut: 0),
            .init(app: "A", host: "127.0.0.1", mobile: false, bytesIn: 400, bytesOut: 0),
            .init(app: "A", host: "1.2.3.4", mobile: false, bytesIn: 300, bytesOut: 0),
            .init(app: "A", host: "i.ytimg.com", mobile: false, bytesIn: 10, bytesOut: 0),
        ])
        let d = await s.topDomains(app: "A", fromDay: "2027-02-01", toDay: "2027-02-01")
        XCTAssertEqual(d.map(\.name), ["YouTube", "SpoofDPI üzerinden", "1.2.3.4", "Yerel ağ"])
        XCTAssertEqual(d.last?.bytes, 1500)
    }

    func testStoreHourlyDomainsRegroupsOldRawRows() async {
        let path = NSTemporaryDirectory() + "dg-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let s = UsageStore(path: path)
        let h = 1_800_000_000 / 3600 * 3600
        await s.add(day: "d", rows: [], hourly: [
            .init(hour: h, app: "A", domain: "192.168.1.5", mobile: false, bytesIn: 70, bytesOut: 0),
            .init(hour: h, app: "A", domain: "10.0.0.2", mobile: false, bytesIn: 30, bytesOut: 0),
            .init(hour: h, app: "A", domain: "127.0.0.1", mobile: false, bytesIn: 5, bytesOut: 0),
            .init(hour: h, app: "A", domain: "YouTube", mobile: false, bytesIn: 20, bytesOut: 0),
            .init(hour: h, app: "A", domain: nil, mobile: false, bytesIn: 1, bytesOut: 0),
        ])
        let rows = await s.hourlyDomains(app: "A", hour: h)
        XCTAssertEqual(rows.map { $0.domain ?? "-" }, ["YouTube", "SpoofDPI üzerinden", "-", "Yerel ağ"])
        XCTAssertEqual(rows.last?.bytes, 100)
    }
}
