import XCTest
@testable import Adalmon

@MainActor
private final class FakeBackend: AdalmonIntentBackend {
    var battery: BatteryStatusAnswer? = BatteryStatusAnswer(level: 78, state: .onBattery, minutesToEmpty: 192, minutesToFull: nil, healthPercent: 86)
    var devices = [DeviceBatteryAnswer(name: "iPhone", level: 79, isCharging: false, isConnected: true),
                   DeviceBatteryAnswer(name: "Klavye", level: 18, isCharging: true, isConnected: true),
                   DeviceBatteryAnswer(name: "Gizli", level: nil, isCharging: false, isConnected: false)]
    var usage = MobileUsageAnswer(todayBytes: 1_260_000_000, dailyCapBytes: 3_000_000_000, cycleUsedBytes: 9_400_000_000,
                                  monthlyCapBytes: 30_000_000_000, isOnMobile: true)
    var opened: [AdalmonRoute] = []
    var throttles: [(String, AppLimit)] = []
    var removed: [String] = []
    var blocked: [(String, Bool)] = []

    func batteryStatus() -> BatteryStatusAnswer? { battery }
    func deviceBatteries() -> [DeviceBatteryAnswer] { devices }
    func mobileUsage() -> MobileUsageAnswer { usage }
    func open(route: AdalmonRoute) { opened.append(route) }
    func setThrottle(appID: String, limit: AppLimit) { throttles.append((appID, limit)) }
    func removeThrottle(appID: String) { removed.append(appID) }
    func setBlockedOnMobile(appID: String, blocked: Bool) { self.blocked.append((appID, blocked)) }
    func knownApps() -> [IntentAppInfo] { [IntentAppInfo(id: "/Applications/Safari.app", name: "Safari"), IntentAppInfo(id: "/Applications/Warp.app", name: "Warp")] }
    func appName(for id: String) -> String { id }
}

@MainActor
final class IntentTests: XCTestCase {
    private var fake = FakeBackend()
    private let app = AppTargetEntity(id: "/Applications/Safari.app", name: "Safari")

    override func setUp() async throws {
        fake = FakeBackend()
        AdalmonIntentHub.backend = fake
    }

    override func tearDown() async throws { AdalmonIntentHub.backend = nil }

    func testThrottleParametersMapToBytesPerSecondBothDirections() async throws {
        _ = try await SetThrottleIntent(app: app, kilobytesPerSecond: 500, onlyOnMobile: true).perform()
        XCTAssertEqual(fake.throttles.count, 1)
        XCTAssertEqual(fake.throttles[0].0, app.id)
        XCTAssertEqual(fake.throttles[0].1, AppLimit(downBytesPerSec: 512_000, upBytesPerSec: 512_000, onlyOnMobile: true))
        _ = try await SetThrottleIntent(app: app, kilobytesPerSecond: 1024).perform()
        XCTAssertEqual(fake.throttles[1].1.onlyOnMobile, false)
        XCTAssertEqual(fake.throttles[1].1.downBytesPerSec, 1_048_576)
    }

    func testThrottleRejectsZeroAndHugeValuesAreClamped() async {
        do {
            _ = try await SetThrottleIntent(app: app, kilobytesPerSecond: 0).perform()
            XCTFail("0 KB/sn reddedilmeli")
        } catch {
            XCTAssertTrue(error is AdalmonIntentError)
        }
        XCTAssertTrue(fake.throttles.isEmpty)
        XCTAssertEqual(IntentMapping.limit(kilobytesPerSecond: .max, onlyOnMobile: false)?.downBytesPerSec, 10_000_000 * 1024)
        XCTAssertNil(IntentMapping.limit(kilobytesPerSecond: -5, onlyOnMobile: false))
    }

    func testRemoveThrottleAndBlockUnblock() async throws {
        _ = try await RemoveThrottleIntent(app: app).perform()
        XCTAssertEqual(fake.removed, [app.id])
        _ = try await SetBlockedOnMobileIntent(app: app, blocked: true).perform()
        _ = try await SetBlockedOnMobileIntent(app: app, blocked: false).perform()
        XCTAssertEqual(fake.blocked.map(\.1), [true, false])
        XCTAssertEqual(fake.blocked.map(\.0), [app.id, app.id])
    }

    func testOpenPageMapsToRoute() async throws {
        for page in [AdalmonPage.battery, .mobile, .widgets, .shortcuts, .processes] {
            _ = try await OpenAdalmonIntent(page: page).perform()
        }
        XCTAssertEqual(fake.opened, [.battery, .mobile, .widgets, .shortcuts, .processes])
        XCTAssertEqual(Set(AdalmonPage.allCases.map(\.route)).count, AdalmonPage.allCases.count)
    }

    func testReadIntentsReturnTurkishText() async throws {
        let battery = try await GetBatteryStatusIntent().perform()
        XCTAssertEqual(battery.value, "Pil %78, pilde; 3 sa 12 dk kaldı.")
        let devices = try await GetDeviceBatteriesIntent().perform()
        XCTAssertEqual(devices.value, "iPhone %79, Klavye %18 (şarjda).")
        let mobile = try await GetMobileUsageIntent().perform()
        XCTAssertEqual(mobile.value, "Bugün mobil veri: 1,3 GB / 3,0 GB; dönem: 9,4 GB / 30 GB.")
    }

    func testBatteryTextVariants() {
        XCTAssertEqual(IntentMapping.batteryText(BatteryStatusAnswer(level: 64, state: .charging, minutesToEmpty: nil, minutesToFull: 40, healthPercent: nil)),
                       "Pil %64, şarj oluyor; %100'e 40 dk.")
        XCTAssertEqual(IntentMapping.batteryText(BatteryStatusAnswer(level: 100, state: .full, minutesToEmpty: nil, minutesToFull: nil, healthPercent: nil)),
                       "Pil %100, tam şarjlı.")
        XCTAssertEqual(IntentMapping.devicesText([]), "Pili okunabilen cihaz yok.")
    }

    func testNoBatteryThrowsAndMissingBackendThrows() async {
        fake.battery = nil
        do { _ = try await GetBatteryStatusIntent().perform(); XCTFail() } catch { XCTAssertTrue(error is AdalmonIntentError) }
        AdalmonIntentHub.backend = nil
        do { _ = try await GetMobileUsageIntent().perform(); XCTFail() } catch { XCTAssertTrue(error is AdalmonIntentError) }
    }

    func testAppEntityQueryUsesBackend() async throws {
        let all = try await AppTargetQuery().suggestedEntities()
        XCTAssertEqual(all.map(\.name), ["Safari", "Warp"])
        let found = try await AppTargetQuery().entities(matching: "war")
        XCTAssertEqual(found.map(\.name), ["Warp"])
        let byID = try await AppTargetQuery().entities(for: ["/x.app"])
        XCTAssertEqual(byID.map(\.id), ["/x.app"])
    }

    func testCatalogCoversEveryIntent() {
        XCTAssertEqual(ShortcutCatalog.entries.count, 7)
        XCTAssertEqual(Set(ShortcutCatalog.entries.map(\.id)).count, 7)
        XCTAssertEqual(AdalmonShortcuts.appShortcuts.count, 6)
    }

    // MARK: Yönlendirme

    func testRouterHandlesURLInDockModeAndFallbackOtherwise() {
        var main = 0, settings = 0
        let dock = SettingsRouter(isDockModeOn: { true })
        dock.attach(showMainWindow: { main += 1 }, showSettingsWindow: { settings += 1 })
        XCTAssertTrue(dock.handle(url: URL(string: "adalmon://battery")!))
        XCTAssertEqual(dock.selectedMainSection, .battery)
        XCTAssertTrue(dock.handle(url: AdalmonRoute.widgets.url))
        XCTAssertEqual(dock.selectedMainSection, .settings(.widgets))
        XCTAssertTrue(dock.handle(url: AdalmonRoute.mobile.url))
        XCTAssertEqual(dock.selectedMainSection, .mobile)
        XCTAssertEqual(main, 3)
        XCTAssertFalse(dock.handle(url: URL(string: "adalmon://yok")!))
        XCTAssertFalse(dock.handle(url: URL(string: "https://example.com")!))
        XCTAssertEqual(main, 3)

        let noDock = SettingsRouter(isDockModeOn: { false })
        noDock.attach(showMainWindow: { main += 1 }, showSettingsWindow: { settings += 1 })
        XCTAssertTrue(noDock.handle(url: AdalmonRoute.battery.url))
        XCTAssertEqual(noDock.selectedSettingsSection, .batteryAlerts)
        XCTAssertEqual(settings, 1)
        XCTAssertEqual(main, 3)
        for route in AdalmonRoute.allCases { _ = route.mainSection; _ = route.settingsFallback }
    }
}
