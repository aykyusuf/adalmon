import XCTest
@testable import Adalmon

/// Faz B: proxy hedef ayrıştırma, FilterConfig çift yönlü decode, engel / Veri Tasarrufu / akış sınıflandırma kararları.
final class FilterPolicyTests: XCTestCase {

    // MARK: ProxyTargetParser

    private func host(_ s: String) -> String? { ProxyTargetParser.host(from: Data(s.utf8)) }

    func testConnectParsesHostAndStripsPort() {
        XCTAssertEqual(host("CONNECT www.youtube.com:443 HTTP/1.1\r\nHost: www.youtube.com:443\r\n\r\n"), "www.youtube.com")
        XCTAssertEqual(host("CONNECT example.com HTTP/1.1\r\n"), "example.com")
        XCTAssertEqual(host("CONNECT example.com:443 HTTP/1.1\n"), "example.com")
    }

    func testConnectIsCaseInsensitiveAndHostLowercased() {
        XCTAssertEqual(host("connect Example.COM:443 HTTP/1.1\r\n"), "example.com")
        XCTAssertEqual(host("Connect api.example.com:8443 http/1.1\r\n"), "api.example.com")
    }

    func testConnectIPv6Literal() {
        XCTAssertEqual(host("CONNECT [::1]:443 HTTP/1.1\r\n"), "::1")
        XCTAssertEqual(host("CONNECT [2001:db8::7]:8443 HTTP/1.1\r\n\r\n"), "2001:db8::7")
    }

    func testPartialLineNeverYieldsTruncatedHost() {
        XCTAssertNil(host("CONNECT exa"))
        XCTAssertNil(host("CONNECT example.com:44"))
        XCTAssertNil(host("CONNECT"))
        XCTAssertNil(host("GET http://exam"))
        // Sürüm belirteci geldiyse satır tamamdır (CRLF olmasa da).
        XCTAssertEqual(host("CONNECT example.com:443 HTTP/1."), "example.com")
        XCTAssertEqual(host("CONNECT example.com:443 HTTP/1.1\r"), "example.com") // CRLF'nin yarısı
    }

    func testMalformedAndBinaryInputReturnsNil() {
        XCTAssertNil(host(""))
        XCTAssertNil(ProxyTargetParser.host(from: Data()))
        XCTAssertNil(host("\r\n\r\n"))
        XCTAssertNil(host("CONNECT  HTTP/1.1\r\n"))
        XCTAssertNil(host("CONNECT ex!ample.com:443 HTTP/1.1\r\n"))
        XCTAssertNil(host("12345 678\r\n"))
        // TLS ClientHello (ikili) host üretmez.
        let hello = Data([0x16, 0x03, 0x01, 0x02, 0x00, 0x01, 0x00, 0x01, 0xfc, 0x03, 0x03, 0x0A, 0x0D, 0x0A])
        XCTAssertNil(ProxyTargetParser.host(from: hello))
        // Aşırı uzun host.
        XCTAssertNil(host("CONNECT \(String(repeating: "a", count: 300)):443 HTTP/1.1\r\n"))
    }

    func testAbsoluteURIGet() {
        XCTAssertEqual(host("GET http://Example.com/index.html HTTP/1.1\r\nHost: example.com\r\n\r\n"), "example.com")
        XCTAssertEqual(host("POST http://api.example.com:8080/x?y=1 HTTP/1.1\r\n"), "api.example.com")
        XCTAssertEqual(host("GET http://user:pw@host.example/ HTTP/1.1\r\n"), "host.example")
        XCTAssertEqual(host("GET http://[::1]:3000/ HTTP/1.1\r\n"), "::1")
        XCTAssertEqual(host("HEAD HTTP://upper.example HTTP/1.1\r\n"), "upper.example")
    }

    func testHostHeaderFallbackForOriginForm() {
        XCTAssertEqual(host("GET /path HTTP/1.1\r\nUser-Agent: x\r\nHost: Site.example:81\r\nAccept: */*\r\n\r\n"), "site.example")
        // Yarım başlık beklenmez.
        XCTAssertNil(host("GET /path HTTP/1.1\r\nHost: site.exa"))
        // Host başlığı yok.
        XCTAssertNil(host("GET /path HTTP/1.1\r\nAccept: */*\r\n\r\n"))
    }

    func testSOCKS5DomainRequest() {
        var b: [UInt8] = [5, 1, 0, 3, 11]
        b += Array("example.com".utf8)
        b += [0x01, 0xBB]
        XCTAssertEqual(ProxyTargetParser.host(from: Data(b)), "example.com")
        XCTAssertNil(ProxyTargetParser.host(from: Data([5, 1, 0]))) // yalnız selamlaşma
        XCTAssertNil(ProxyTargetParser.host(from: Data(Array(b.prefix(8))))) // kesik ad
    }

    func testParserOnlyInspectsFirstKilobyte() {
        var s = "GET /x HTTP/1.1\r\n" + String(repeating: "X-Pad: 1\r\n", count: 200)
        s += "Host: late.example\r\n\r\n"
        XCTAssertNil(host(s)) // Host 1024. bayttan sonra: bakılmaz
    }

    // MARK: FilterConfig çift yönlü decode

    func testOldAppJSONDecodesInNewFilterWithDefaults() throws {
        let old = #"{"proxyPorts":[8080],"proxyOwnerPaths":["/x/spoofdpi"],"blockedOnMobile":["/A.app"],"forceMobile":true,"limits":{}}"#
        let cfg = try JSONDecoder().decode(FilterConfig.self, from: Data(old.utf8))
        XCTAssertTrue(cfg.blockedAlways.isEmpty)
        XCTAssertFalse(cfg.dataSaverActive)
        XCTAssertTrue(cfg.dataSaverAllow.isEmpty)
        XCTAssertEqual(cfg.blockedOnMobile, ["/A.app"])
    }

    func testNewConfigRoundTripsEveryNewField() throws {
        var cfg = FilterConfig(proxyPorts: [8080], proxyOwnerPaths: ["/x/spoofdpi"], blockedOnMobile: ["/B.app"], forceMobile: true,
                               limits: ["/A.app": AppLimit(downBytesPerSec: 100, upBytesPerSec: nil, onlyOnMobile: true)])
        cfg.blockedAlways = ["/Z.app", "/Y.app"]
        cfg.dataSaverActive = true
        cfg.dataSaverAllow = ["/Applications/Mail.app", "/Applications/Slack.app"]
        let back = try JSONDecoder().decode(FilterConfig.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back, cfg)
        XCTAssertEqual(back.blockedAlways, ["/Z.app", "/Y.app"])
        XCTAssertTrue(back.dataSaverActive)
        XCTAssertEqual(back.dataSaverAllow.count, 2)
    }

    /// Eski filtrenin yapılandırması (yalnız eski alanlar) yeni JSON'u çözebilmeli: bilinmeyen anahtarlar yok sayılır.
    func testOldFilterDecoderIgnoresNewKeys() throws {
        struct OldFilterConfig: Codable {
            var proxyPorts: [Int] = []
            var proxyOwnerPaths: [String] = []
            var blockedOnMobile: [String] = []
            var forceMobile: Bool = false
            var limits: [String: AppLimit] = [:]
        }
        var cfg = FilterConfig(proxyPorts: [8080], blockedOnMobile: ["/B.app"])
        cfg.blockedAlways = ["/Z.app"]
        cfg.dataSaverActive = true
        cfg.dataSaverAllow = ["/Q.app"]
        let old = try JSONDecoder().decode(OldFilterConfig.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(old.proxyPorts, [8080])
        XCTAssertEqual(old.blockedOnMobile, ["/B.app"])
    }

    // MARK: Sınıflandırma

    private let spoof = "/Users/u/Desktop/spoofdpi"
    private func cfg() -> FilterConfig { FilterConfig(proxyPorts: [8080], proxyOwnerPaths: [spoof]) }

    func testClassifyDirectProxiedEgressAndLoopbackOther() {
        let c = cfg()
        XCTAssertEqual(FlowPolicy.classify(isLoopback: false, isOutbound: true, remotePort: 443, executablePath: "/Applications/Safari.app", config: c), .direct)
        XCTAssertEqual(FlowPolicy.classify(isLoopback: true, isOutbound: true, remotePort: 8080, executablePath: "/Applications/Safari.app", config: c), .proxied)
        XCTAssertEqual(FlowPolicy.classify(isLoopback: false, isOutbound: true, remotePort: 443, executablePath: spoof, config: c), .proxyEgress)
        // Loopback ama proxy portu değil / gelen / sahibi proxy süreci → ilgisiz.
        XCTAssertNil(FlowPolicy.classify(isLoopback: true, isOutbound: true, remotePort: 9999, executablePath: "/Applications/X.app", config: c))
        XCTAssertNil(FlowPolicy.classify(isLoopback: true, isOutbound: false, remotePort: 8080, executablePath: "/Applications/X.app", config: c))
        XCTAssertNil(FlowPolicy.classify(isLoopback: true, isOutbound: true, remotePort: 8080, executablePath: spoof, config: c))
        // Proxy yokken loopback hiç sayılmaz.
        XCTAssertNil(FlowPolicy.classify(isLoopback: true, isOutbound: true, remotePort: 8080, executablePath: "/Applications/X.app", config: FilterConfig()))
    }

    // MARK: blockedAlways / blockedOnMobile

    func testBlockedAlwaysAppliesOnWifiAndMobile() {
        var c = cfg()
        c.blockedAlways = ["/Applications/A.app"]
        c.blockedOnMobile = ["/Applications/B.app"]
        XCTAssertTrue(FlowPolicy.shouldBlock(app: "/Applications/A.app", kind: .direct, expensive: false, config: c))
        XCTAssertTrue(FlowPolicy.shouldBlock(app: "/Applications/A.app", kind: .proxied, expensive: true, config: c))
        XCTAssertFalse(FlowPolicy.shouldBlock(app: "/Applications/B.app", kind: .direct, expensive: false, config: c)) // yalnız mobil
        XCTAssertTrue(FlowPolicy.shouldBlock(app: "/Applications/B.app", kind: .direct, expensive: true, config: c))
        XCTAssertFalse(FlowPolicy.shouldBlock(app: "/Applications/C.app", kind: .direct, expensive: true, config: c))
    }

    func testBlockNeverAppliesToProxyEgress() {
        var c = cfg()
        c.blockedAlways = [spoof]
        c.blockedOnMobile = [spoof]
        XCTAssertFalse(FlowPolicy.shouldBlock(app: spoof, kind: .proxyEgress, expensive: true, config: c))
    }

    // MARK: Veri Tasarrufu

    private func saver(_ allow: Set<String> = []) -> FilterConfig {
        var c = cfg()
        c.dataSaverActive = true
        c.dataSaverAllow = allow
        return c
    }

    private func drop(app: String = "/Applications/Chrome.app", signing: String = "com.google.Chrome", path: String? = nil,
                      kind: FlowKind = .direct, outbound: Bool = true, port: Int = 443, expensive: Bool = true,
                      config: FilterConfig) -> Bool {
        FlowPolicy.shouldDropForDataSaver(app: app, signingID: signing, executablePath: path ?? app, kind: kind,
                                          isOutbound: outbound, remotePort: port, expensive: expensive, config: config)
    }

    func testDataSaverDropsNonAllowedOnlyWhenActiveAndOnMobile() {
        XCTAssertTrue(drop(config: saver()))
        XCTAssertFalse(drop(expensive: false, config: saver())) // Wi-Fi: dokunma
        var off = saver(); off.dataSaverActive = false
        XCTAssertFalse(drop(config: off))
        XCTAssertFalse(drop(outbound: false, config: saver())) // gelen akış
    }

    func testDataSaverAllowlistWins() {
        XCTAssertFalse(drop(config: saver(["/Applications/Chrome.app"])))
        XCTAssertTrue(drop(app: "/Applications/Slack.app", signing: "com.tinyspeck.slackmacgap", config: saver(["/Applications/Chrome.app"])))
    }

    func testDataSaverBlocksOriginatingProxiedFlowButNeverProxyEgress() {
        // Orijin uygulamanın loopback (proxied) akışı düşer…
        XCTAssertTrue(drop(kind: .proxied, port: 8080, config: saver()))
        // …SpoofDPI'ın dış akışı asla.
        XCTAssertFalse(drop(app: spoof, signing: "", path: spoof, kind: .proxyEgress, config: saver()))
        XCTAssertFalse(drop(kind: .proxyEgress, config: saver()))
        // İzinli uygulamanın proxied akışı geçer.
        XCTAssertFalse(drop(kind: .proxied, port: 8080, config: saver(["/Applications/Chrome.app"])))
    }

    func testDataSaverNeverDropsAdalmonDNSOrProxyOwner() {
        let c = saver()
        XCTAssertFalse(drop(app: "/Applications/Adalmon.app", signing: IPC.appBundleID, kind: .proxied, port: 8080, config: c))
        XCTAssertFalse(drop(app: "/Applications/Adalmon.app", signing: IPC.appBundleID, config: c))
        XCTAssertFalse(drop(app: "/x/f", signing: IPC.filterBundleID, path: "/x/f", config: c))
        XCTAssertFalse(drop(port: 53, config: c))
        XCTAssertFalse(drop(port: 853, config: c))
        XCTAssertFalse(drop(app: spoof, signing: "", path: spoof, config: c)) // proxy sahibinin doğrudan akışı
    }

    func testDataSaverFailsOpenOnUnknownIdentity() {
        let c = saver()
        XCTAssertFalse(drop(app: "unknown", signing: "", path: "", config: c))
        XCTAssertFalse(drop(app: "pid:123", signing: "", path: "", config: c))
        XCTAssertFalse(drop(app: "pid:123", signing: "x", path: "/tmp/x", config: c))
    }

    func testDataSaverExemptsSystemDaemonsButNotUserAppsInSystemFolders() {
        let c = saver()
        for path in ["/usr/sbin/mDNSResponder", "/usr/libexec/trustd", "/usr/libexec/networkserviceproxy",
                     "/usr/libexec/symptomsd", "/usr/sbin/configd",
                     "/System/Library/PrivateFrameworks/ApplePushService.framework/apsd",
                     "/System/Library/PrivateFrameworks/IDS.framework/identityservicesd",
                     "/System/Library/Frameworks/SystemConfiguration.framework/Versions/A/Helpers/nesessionmanager",
                     // OS Cryptex'indeki sistem ikilisi, kanonik yola çevrilir.
                     "/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/Foo.framework/foo"] {
            XCTAssertFalse(drop(app: path, signing: "com.apple.x", path: path, config: c), path)
        }
        // Kullanıcı uygulamaları: Safari (Cryptex), Mail, /Applications — muaf DEĞİL.
        XCTAssertTrue(drop(app: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", signing: "com.apple.Safari",
                           path: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", config: c))
        XCTAssertTrue(drop(app: "/System/Applications/Mail.app", signing: "com.apple.mail", path: "/System/Applications/Mail.app", config: c))
        XCTAssertTrue(drop(app: "/usr/bin/curl", signing: "com.apple.curl", path: "/usr/bin/curl", config: c))
    }

    func testDataSaverBandwidthHogsAreNotExemptUnlessAllowlisted() {
        for path in ["/usr/libexec/nsurlsessiond", "/usr/libexec/softwareupdated", "/usr/libexec/mobileassetd",
                     "/System/Library/PrivateFrameworks/CloudKitDaemon.framework/Support/cloudd",
                     "/System/Library/PrivateFrameworks/CloudDocsDaemon.framework/Versions/A/Support/bird",
                     "/System/Library/PrivateFrameworks/PhotoAnalysis.framework/Versions/A/Support/photoanalysisd",
                     "/System/Library/PrivateFrameworks/MediaAnalysis.framework/Versions/A/mediaanalysisd"] {
            XCTAssertTrue(drop(app: path, signing: "com.apple.x", path: path, config: saver()), path)
            XCTAssertFalse(drop(app: path, signing: "com.apple.x", path: path, config: saver([path])), path)
        }
    }

    func testUnattributedWebKitNetworkingIsNotExempt() {
        let xpc = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.Networking.xpc"
        XCTAssertTrue(drop(app: xpc, signing: "com.apple.WebKit.Networking", path: xpc, config: saver()))
        // Hosting uygulamaya atfedildiyse (app = Safari, yol hâlâ WebKit) karar izin listesine bakar.
        let safari = "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
        XCTAssertFalse(drop(app: safari, signing: "com.apple.WebKit.Networking", path: xpc, config: saver([safari])))
        XCTAssertTrue(drop(app: safari, signing: "com.apple.WebKit.Networking", path: xpc, config: saver()))
    }

    // MARK: Veri gözetimi (verdict planı)

    func testDataTapPlanPerFlowKind() {
        // Proxied: Wi-Fi'de de mobilde de yalnız ilk giden 1024 bayt, gelen taraf yok.
        XCTAssertEqual(FlowPolicy.dataTap(kind: .proxied, expensive: false), .peekOutboundForTarget(bytes: 1024))
        XCTAssertEqual(FlowPolicy.dataTap(kind: .proxied, expensive: true), .peekOutboundForTarget(bytes: 1024))
        XCTAssertEqual(ProxyTargetParser.maxInspectBytes, FlowPolicy.targetPeekBytes)
        // Doğrudan: Wi-Fi'de dokunma yok; mobilde var olan gelen-veri izleme.
        XCTAssertEqual(FlowPolicy.dataTap(kind: .direct, expensive: false), .none)
        XCTAssertEqual(FlowPolicy.dataTap(kind: .direct, expensive: true), .mobileInbound)
        XCTAssertEqual(FlowPolicy.dataTap(kind: .proxyEgress, expensive: true), .none)
        XCTAssertEqual(FlowPolicy.dataTap(kind: .proxyEgress, expensive: false), .none)
    }

    // MARK: Uygulama tarafı

    func testEffectiveConfigCarriesBlockedAlways() {
        var out = RuleOutput()
        out.blockedAlways = ["/Applications/A.app"]
        out.blocked["/Applications/A.app"] = [.rule(UUID())]
        let eff = EffectiveConfigBuilder.build(manualLimits: [:], manualBlocked: [], output: out, onMobile: false)
        XCTAssertEqual(eff.blockedAlways, ["/Applications/A.app"])
        XCTAssertEqual(eff.blocked, ["/Applications/A.app"])
        XCTAssertFalse(out.isEmpty)
    }

    func testWebKitNetworkingDetectionForAttribution() {
        XCTAssertTrue(FlowPolicy.isWebKitHelper(executablePath: "", signingID: "com.apple.WebKit.Networking"))
        XCTAssertTrue(FlowPolicy.isWebKitHelper(executablePath: "/System/Library/Frameworks/WebKit.framework/x", signingID: ""))
        XCTAssertFalse(FlowPolicy.isWebKitHelper(executablePath: "/Applications/Google Chrome.app", signingID: "com.google.Chrome"))
    }

    // MARK: İnceleme düzeltmeleri

    func testOwnerUnknownFailsOpenForBlockAndDataSaver() {
        var c = FilterConfig(proxyPorts: [8080], proxyOwnerPaths: [])
        c.blockedAlways = [spoof]
        c.dataSaverActive = true
        // SpoofDPI sahibi henüz bilinmiyor: kendi akışı .direct görünür ama engellenmemeli.
        XCTAssertFalse(FlowPolicy.shouldBlock(app: spoof, kind: .direct, expensive: true, config: c))
        XCTAssertFalse(FlowPolicy.shouldDropForDataSaver(app: spoof, signingID: "", executablePath: spoof, kind: .direct,
                                                         isOutbound: true, remotePort: 443, expensive: true, config: c))
        // Orijin uygulamanın proxied akışı yine engellenebilir.
        c.blockedAlways = ["/Applications/X.app"]
        XCTAssertTrue(FlowPolicy.shouldBlock(app: "/Applications/X.app", kind: .proxied, expensive: false, config: c))
    }

    func testAdalmonItselfNeverBlocked() {
        var c = cfg()
        c.blockedAlways = ["/Applications/Adalmon.app"]
        XCTAssertFalse(FlowPolicy.shouldBlock(app: "/Applications/Adalmon.app", kind: .direct, expensive: false,
                                              config: c, signingID: IPC.appBundleID))
    }
}
