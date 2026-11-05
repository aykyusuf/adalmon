import XCTest
@testable import Adalmon

final class ThrottleTests: XCTestCase {
    private let chrome = "/Applications/Google Chrome.app"
    private let spoof = "/Users/u/Desktop/spoofdpi"

    // MARK: TokenBucket

    func testBucketSustainedRateMatchesLimit() {
        // 1 MB/s, 64 KB parçalar: 10 MB'ı aktarmanın toplam süresi ≈ 10 sn (artı ilk patlama payı).
        let rate = 1024 * 1024
        var b = TokenBucket(bytesPerSecond: rate, burstSeconds: 0.25, now: 0)
        var now = 0.0
        let chunk = 64 * 1024
        let total = 10 * rate
        var sent = 0
        while sent < total {
            now += b.reserve(chunk, now: now) // bekle, sonra gönder (aktarım anlık varsayılır)
            sent += chunk
        }
        // Son parçanın başladığı an: (total - chunk) / rate.
        XCTAssertEqual(now, Double(total - chunk) / Double(rate), accuracy: 0.001)
    }

    func testBucketFirstChunkIsFreeThenPaced() {
        var b = TokenBucket(bytesPerSecond: 100_000, burstSeconds: 0, now: 10)
        XCTAssertEqual(b.reserve(50_000, now: 10), 0, accuracy: 1e-9)
        XCTAssertEqual(b.reserve(50_000, now: 10), 0.5, accuracy: 1e-9)
        XCTAssertEqual(b.reserve(100_000, now: 10), 1.0, accuracy: 1e-9)
    }

    func testBucketIdleCreditIsCappedByBurst() {
        var b = TokenBucket(bytesPerSecond: 100_000, burstSeconds: 0.25, now: 0)
        // 100 sn boşta: yalnızca 0.25 sn'lik (25 KB) kredi birikir.
        XCTAssertEqual(b.reserve(25_000, now: 100), 0, accuracy: 1e-9)
        XCTAssertEqual(b.reserve(25_000, now: 100), 0, accuracy: 1e-9)
        XCTAssertEqual(b.reserve(100_000, now: 100), 0.25, accuracy: 1e-9)
    }

    func testBucketChunkLargerThanBurst() {
        // Parça kovadan büyük olsa bile kilitlenmez; sonraki parça doğru gecikir.
        var b = TokenBucket(bytesPerSecond: 10_000, burstSeconds: 0.1, now: 0)
        XCTAssertEqual(b.reserve(64 * 1024, now: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(b.reserve(1, now: 0), 6.5536, accuracy: 1e-6)
    }

    func testBucketRateChangeAppliesToNextReservation() {
        var b = TokenBucket(bytesPerSecond: 1000, burstSeconds: 0, now: 0)
        _ = b.reserve(1000, now: 0)        // sıradaki boş an: 1.0
        b.setRate(2000)
        XCTAssertEqual(b.reserve(1000, now: 0), 1.0, accuracy: 1e-9) // sıradaki: 1.5
        XCTAssertEqual(b.reserve(0, now: 0), 1.5, accuracy: 1e-9)
    }

    // MARK: Config Codable

    func testOldConfigJSONWithoutLimitsDecodes() throws {
        let old = #"{"proxyPorts":[8080],"proxyOwnerPaths":["/x/spoofdpi"],"blockedOnMobile":["/A.app"],"forceMobile":true}"#
        let cfg = try JSONDecoder().decode(FilterConfig.self, from: Data(old.utf8))
        XCTAssertEqual(cfg.proxyPorts, [8080])
        XCTAssertEqual(cfg.proxyOwnerPaths, ["/x/spoofdpi"])
        XCTAssertEqual(cfg.blockedOnMobile, ["/A.app"])
        XCTAssertTrue(cfg.forceMobile)
        XCTAssertTrue(cfg.limits.isEmpty)
    }

    func testEmptyConfigJSONDecodes() throws {
        let cfg = try JSONDecoder().decode(FilterConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(cfg, FilterConfig())
    }

    func testConfigRoundTripWithLimits() throws {
        let cfg = FilterConfig(proxyPorts: [8080], proxyOwnerPaths: [spoof], blockedOnMobile: [], forceMobile: false,
                               limits: [chrome: AppLimit(downBytesPerSec: 1_048_576, upBytesPerSec: nil, onlyOnMobile: true)])
        let back = try JSONDecoder().decode(FilterConfig.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back, cfg)
        XCTAssertEqual(back.limits[chrome]?.downBytesPerSec, 1_048_576)
        XCTAssertNil(back.limits[chrome]?.upBytesPerSec)
    }

    // MARK: Karar fonksiyonu

    private func config(onlyOnMobile: Bool = false) -> FilterConfig {
        FilterConfig(proxyPorts: [8080], proxyOwnerPaths: [spoof], blockedOnMobile: [], forceMobile: false,
                     limits: [chrome: AppLimit(downBytesPerSec: 1_048_576, onlyOnMobile: onlyOnMobile),
                              spoof: AppLimit(downBytesPerSec: 1000)])
    }

    private func handle(_ app: String, path: String? = nil, signing: String = "com.google.Chrome.helper",
                        loopback: Bool = false, port: Int = 443, tcp: Bool = true,
                        expensive: Bool = false, cfg: FilterConfig? = nil) -> Bool {
        ThrottlePolicy.shouldHandle(app: app, executablePath: path ?? app + "/Contents/MacOS/x", signingID: signing,
                                    isLoopback: loopback, remotePort: port, isTCP: tcp,
                                    expensive: expensive, config: cfg ?? config())
    }

    func testLimitedAppDirectFlowIsHandled() {
        XCTAssertTrue(handle(chrome))
    }

    func testUnlimitedAppIsNotHandled() {
        XCTAssertFalse(handle("/Applications/Safari.app", signing: "com.apple.Safari"))
    }

    func testProxyOwnerIsNeverHandledEvenIfLimited() {
        XCTAssertFalse(handle(spoof, path: spoof, signing: "spoofdpi"))
    }

    func testOwnExtensionAndAppAreNeverHandled() {
        XCTAssertFalse(handle(chrome, signing: IPC.filterBundleID))
        XCTAssertFalse(handle(chrome, signing: IPC.appBundleID))
    }

    func testLoopbackToProxyPortIsHandled() {
        XCTAssertTrue(handle(chrome, loopback: true, port: 8080))
    }

    func testLoopbackToOtherPortIsNotHandled() {
        XCTAssertFalse(handle(chrome, loopback: true, port: 3000))
    }

    func testUDPIsNotHandled() {
        XCTAssertFalse(handle(chrome, tcp: false))
    }

    func testOnlyOnMobileRespectsPath() {
        let cfg = config(onlyOnMobile: true)
        XCTAssertFalse(handle(chrome, expensive: false, cfg: cfg))
        XCTAssertTrue(handle(chrome, expensive: true, cfg: cfg))
    }

    func testBlockedOnMobileIsLeftToFilterWhenExpensive() {
        var cfg = config()
        cfg.blockedOnMobile = [chrome]
        XCTAssertFalse(handle(chrome, expensive: true, cfg: cfg))
        XCTAssertTrue(handle(chrome, expensive: false, cfg: cfg))
    }

    func testEmptyLimitIsIgnored() {
        var cfg = config()
        cfg.limits[chrome] = AppLimit(downBytesPerSec: nil, upBytesPerSec: 0)
        XCTAssertFalse(handle(chrome, cfg: cfg))
    }

    func testQUICDropOnlyForLimitedApps() {
        let cfg = config()
        XCTAssertTrue(ThrottlePolicy.shouldDropQUIC(app: chrome, isUDP: true, remotePort: 443, isLoopback: false,
                                                    expensive: false, config: cfg))
        XCTAssertFalse(ThrottlePolicy.shouldDropQUIC(app: "/Applications/Safari.app", isUDP: true, remotePort: 443,
                                                     isLoopback: false, expensive: false, config: cfg))
        XCTAssertFalse(ThrottlePolicy.shouldDropQUIC(app: chrome, isUDP: false, remotePort: 443, isLoopback: false,
                                                     expensive: false, config: cfg))
        XCTAssertFalse(ThrottlePolicy.shouldDropQUIC(app: chrome, isUDP: true, remotePort: 53, isLoopback: false,
                                                     expensive: false, config: cfg))
        XCTAssertFalse(ThrottlePolicy.shouldDropQUIC(app: chrome, isUDP: true, remotePort: 443, isLoopback: false,
                                                     expensive: false, config: config(onlyOnMobile: true)))
    }

    func testRateText() {
        XCTAssertEqual(AppModel.rateText(250 * 1024), "250 KB/s")
        XCTAssertEqual(AppModel.rateText(1024 * 1024), "1 MB/s")
        XCTAssertEqual(AppModel.rateText(1536 * 1024), "1.5 MB/s")
    }
}
