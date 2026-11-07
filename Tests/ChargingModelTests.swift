import XCTest
@testable import Adalmon

/// Gerçek SMAppService kaydı ve XPC YOK: sahte kayıt + sahte istemci.
@MainActor
final class FakeRegistration: HelperRegistering {
    var state: HelperInstallState = .notInstalled
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var openedSettings = 0
    var registerResult: HelperInstallState = .requiresApproval

    func register() throws { registerCalls += 1; state = registerResult }
    func unregister() async throws { unregisterCalls += 1; state = .notInstalled }
    func openLoginItemsSettings() { openedSettings += 1 }
}

final class FakeClient: ChargeHelperClienting, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [HelperCommand] = []
    private var blocking: [HelperCommand] = []
    var reply = HelperReply.success(HelperStatus())

    var commands: [HelperCommand] { lock.lock(); defer { lock.unlock() }; return sent }
    var blockingCommands: [HelperCommand] { lock.lock(); defer { lock.unlock() }; return blocking }

    func send(_ command: HelperCommand) async -> Result<HelperReply, ChargeHelperError> {
        record(command)
        return .success(reply)
    }

    private func record(_ command: HelperCommand) { lock.lock(); sent.append(command); lock.unlock() }

    func sendBlocking(_ command: HelperCommand, timeout: TimeInterval) -> Result<HelperReply, ChargeHelperError> {
        lock.lock(); blocking.append(command); lock.unlock()
        return .success(reply)
    }
}

@MainActor
final class ChargingModelTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "adalmon.tests.charging.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func make(state: HelperInstallState = .notInstalled, flag: Bool = false) -> (ChargingModel, FakeRegistration, FakeClient) {
        let registration = FakeRegistration()
        registration.state = state
        let client = FakeClient()
        let prefs = ChargingPreferences(defaults: defaults)
        prefs.featureEnabled = flag
        return (ChargingModel(registration: registration, client: client, prefs: prefs), registration, client)
    }

    func testFeatureFlagsDefaultOff() {
        let p = ChargingPreferences(defaults: defaults)
        XCTAssertFalse(p.featureEnabled)
        XCTAssertFalse(p.ledFeatureEnabled)
        XCTAssertFalse(p.limitEnabled)
        XCTAssertTrue(p.restoreOnQuit, "güvenli varsayılan: kapanınca normal şarj")
        XCTAssertEqual(p.limit, 80)
        XCTAssertEqual(p.sailingGap, 5)
        XCTAssertEqual(p.led, .auto)
    }

    func testPreferenceClamping() {
        XCTAssertEqual(ChargingPreferences.clampLimit(10), 50)
        XCTAssertEqual(ChargingPreferences.clampLimit(999), 100)
        XCTAssertEqual(ChargingPreferences.clampLimit(83), 85)
        XCTAssertEqual(ChargingPreferences.clampGap(1), 5)
        XCTAssertEqual(ChargingPreferences.clampGap(11), 10)
        XCTAssertEqual(ChargingPreferences.sailingFloor(limit: 80, gap: 5), 75)
        XCTAssertEqual(ChargingPreferences.sailingFloor(limit: 50, gap: 15), 35)
        XCTAssertGreaterThanOrEqual(ChargingPreferences.sailingFloor(limit: 50, gap: 100), HelperConstants.hardFloorPercent)
        for limit in stride(from: 50, through: 100, by: 5) {
            for gap in [5, 10, 15] {
                let floor = ChargingPreferences.sailingFloor(limit: limit, gap: gap)
                XCTAssertNil(ChargeConfig.validate(limit: limit, sailingFloor: floor), "limit \(limit) gap \(gap)")
            }
        }
    }

    func testFlagOffMakesNoHelperCalls() async {
        let (model, registration, client) = make(state: .enabled, flag: false)
        await model.refreshStatus()
        model.startIfNeeded()
        model.applicationWillTerminate()
        XCTAssertTrue(client.commands.isEmpty)
        XCTAssertTrue(client.blockingCommands.isEmpty)
        XCTAssertEqual(registration.registerCalls, 0)
        XCTAssertNil(model.status)
    }

    func testInstallFlowRequiresApproval() async {
        let (model, registration, _) = make()
        await model.install()
        XCTAssertEqual(registration.registerCalls, 1)
        XCTAssertEqual(model.installState, .requiresApproval)
        model.openLoginItemsSettings()
        XCTAssertEqual(registration.openedSettings, 1)
    }

    func testUninstallResetsBeforeUnregistering() async {
        let (model, registration, client) = make(state: .enabled, flag: true)
        model.refreshInstallState()
        await model.uninstall()
        XCTAssertEqual(client.commands, [.resetAll])
        XCTAssertEqual(registration.unregisterCalls, 1)
        XCTAssertEqual(model.installState, .notInstalled)
    }

    func testDisableEverythingSendsResetAndTurnsFlagOff() async {
        let (model, _, client) = make(state: .enabled, flag: true)
        await model.setLimitEnabled(true)
        client.reply = .success(HelperStatus())
        await model.disableEverything()
        XCTAssertEqual(client.commands.last, .resetAll)
        XCTAssertFalse(model.featureEnabled)
        XCTAssertFalse(model.limitEnabled)
        XCTAssertFalse(ChargingPreferences(defaults: defaults).featureEnabled)
        XCTAssertFalse(ChargingPreferences(defaults: defaults).limitEnabled)
        XCTAssertEqual(client.commands.filter { $0 == .resetAll }.count, 1, "yinelenen sıfırlama yok")
    }

    func testSetLimitSendsValidatedCommand() async {
        let (model, _, client) = make(state: .enabled, flag: true)
        await model.setLimitEnabled(true)
        await model.setLimit(85)
        XCTAssertEqual(client.commands, [
            .setChargeLimit(enabled: true, limit: 80, sailingFloor: 75, topUp: false),
            .setChargeLimit(enabled: true, limit: 85, sailingFloor: 80, topUp: false),
        ])
    }

    func testTopUpCommand() async {
        let (model, _, client) = make(state: .enabled, flag: true)
        await model.startTopUp()
        XCTAssertEqual(client.commands, [.setChargeLimit(enabled: true, limit: 80, sailingFloor: 75, topUp: true)])
    }

    func testQuitRestoresOnlyWhenSettingSaysSo() {
        let (model, _, client) = make(state: .enabled, flag: true)
        model.applicationWillTerminate()
        XCTAssertEqual(client.blockingCommands, [.resetAll])

        let (keep, _, keepClient) = make(state: .enabled, flag: true)
        keep.restoreOnQuit = false
        keep.applicationWillTerminate()
        XCTAssertTrue(keepClient.blockingCommands.isEmpty)
    }

    func testVersionMismatchIsReported() async {
        let (model, _, client) = make(state: .enabled, flag: true)
        var status = HelperStatus()
        status.protocolVersion = 99
        client.reply = .success(status)
        await model.refreshStatus()
        XCTAssertEqual(model.errorText, HelperErrorCode.versionMismatch.message)
    }
}
