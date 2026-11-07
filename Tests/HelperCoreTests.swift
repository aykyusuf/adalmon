import XCTest
@testable import Adalmon

final class HelperCoreTests: XCTestCase {
    private let limit80 = HelperPersistedState(config: ChargeConfig(enabled: true, limit: 80, sailingFloor: 75), ledMode: .auto)

    // MARK: Bu Mac (CHTE/CH0B/CH0C yok)

    func testUnsupportedMachineNeverWritesAnything() async {
        let rig = CoreRig(smc: .thisMac(), level: 95)
        await rig.core.start()
        let reply = await rig.core.handle(.setChargeLimit(enabled: true, limit: 80, sailingFloor: 75, topUp: false))
        XCTAssertFalse(reply.ok)
        XCTAssertEqual(reply.error, .unsupported)
        XCTAssertFalse(reply.status.config.enabled)
        XCTAssertNil(reply.status.inhibitMethod)
        let manual = await rig.core.handle(.setChargingInhibited(true, ttlSeconds: 600))
        XCTAssertEqual(manual.error, .unsupported)
        XCTAssertTrue(rig.smc.writes.isEmpty, "destek yokken SMC'ye hiçbir yazma olmamalı")
    }

    func testPersistedEnabledConfigIsDroppedWhenUnsupported() async {
        let rig = CoreRig(smc: .thisMac(), level: 95, saved: limit80)
        await rig.core.start()
        let status = await rig.core.status()
        XCTAssertFalse(status.config.enabled)
        XCTAssertTrue(rig.smc.writes.isEmpty)
        XCTAssertEqual(rig.scheduler.calls, [], "zamanlayıcı hiç açılmamalı")
    }

    func testLEDUnsupportedWithoutKey() async {
        let rig = CoreRig(smc: .legacy())
        await rig.core.start()
        let reply = await rig.core.handle(.setMagSafeLED(.green))
        XCTAssertEqual(reply.error, .unsupported)
        XCTAssertTrue(rig.smc.writes.isEmpty)
    }

    func testResetAllOnThisMacWritesNothing() async {
        let rig = CoreRig(smc: .thisMac(), level: 90)
        await rig.core.start()
        let reply = await rig.core.handle(.resetAll)
        XCTAssertTrue(reply.ok)
        XCTAssertTrue(rig.smc.writes.isEmpty, "LED'e dokunulmadıysa resetAll hiçbir SMC anahtarına yazmamalı")
    }

    func testResetAllRestoresLEDOnlyWhenWeChangedIt() async {
        let rig = CoreRig(smc: .chte(), level: 70)
        await rig.core.start()
        _ = await rig.core.handle(.resetAll)
        XCTAssertTrue(rig.smc.writes.isEmpty)
        _ = await rig.core.handle(.setMagSafeLED(.orange))
        _ = await rig.core.handle(.resetAll)
        XCTAssertEqual(rig.smc.value(.aclc), [0])
    }

    // MARK: Başlangıç emniyeti

    func testStartWithoutConfigReleasesStaleInhibit() async {
        let rig = CoreRig(smc: .chte(inhibited: true), level: 90)
        await rig.core.start()
        XCTAssertFalse(rig.inhibited, "çökme sonrası kalan engel kaldırılmalı")
        XCTAssertEqual(rig.smc.writes.count, 1)
    }

    func testStartWithoutConfigAndNoInhibitDoesNotWrite() async {
        let rig = CoreRig(smc: .chte(inhibited: false), level: 90)
        await rig.core.start()
        XCTAssertTrue(rig.smc.writes.isEmpty)
    }

    func testStartWithSavedLimitEnforcesImmediately() async {
        let rig = CoreRig(smc: .chte(), level: 85, saved: limit80)
        await rig.core.start()
        XCTAssertTrue(rig.inhibited)
        XCTAssertEqual(rig.scheduler.calls, [true])
    }

    func testInvalidSavedConfigFallsBackToOff() async {
        let bad = HelperPersistedState(config: ChargeConfig(enabled: true, limit: 80, sailingFloor: 90), ledMode: .auto)
        let rig = CoreRig(smc: .chte(inhibited: true), level: 85, saved: bad)
        await rig.core.start()
        let status = await rig.core.status()
        XCTAssertFalse(status.config.enabled)
        XCTAssertFalse(rig.inhibited)
    }

    // MARK: Döngü

    func testHysteresisLoopOnSupportedMac() async {
        let rig = CoreRig(smc: .chte(), level: 70)
        await rig.core.start()
        _ = await rig.core.handle(.setChargeLimit(enabled: true, limit: 80, sailingFloor: 75, topUp: false))
        XCTAssertFalse(rig.inhibited)
        rig.battery.set(80); await rig.core.tick()
        XCTAssertTrue(rig.inhibited)
        rig.battery.set(77); await rig.core.tick()
        XCTAssertTrue(rig.inhibited, "seyir: 75'in üstünde engelli kalır")
        rig.battery.set(74); await rig.core.tick()
        XCTAssertFalse(rig.inhibited, "75'in altında şarj yeniden başlar")
    }

    func testWatchdogAndUnplugRelease() async {
        let rig = CoreRig(smc: .chte(), level: 85, saved: limit80)
        await rig.core.start()
        XCTAssertTrue(rig.inhibited)
        rig.battery.set(15); await rig.core.tick()
        XCTAssertFalse(rig.inhibited, "bekçi: %20 altında şarj serbest")
        rig.battery.set(85); await rig.core.tick()
        XCTAssertTrue(rig.inhibited)
        rig.battery.set(85, plugged: false); await rig.core.tick()
        XCTAssertFalse(rig.inhibited, "fiş çekilince engel kalkar")
    }

    func testBatteryUnreadableReleases() async {
        let rig = CoreRig(smc: .chte(), level: 85, saved: limit80)
        await rig.core.start()
        rig.battery.clear(); await rig.core.tick()
        XCTAssertFalse(rig.inhibited)
    }

    func testLegacyKeysWriteBoth() async {
        let rig = CoreRig(smc: .legacy(), level: 90, saved: limit80)
        await rig.core.start()
        XCTAssertEqual(rig.smc.value(.ch0b), [2])
        XCTAssertEqual(rig.smc.value(.ch0c), [2])
        let status = await rig.core.status()
        XCTAssertEqual(status.inhibitMethod, .ch0bc)
        XCTAssertEqual(status.isInhibitingCharge, true)
    }

    // MARK: Hata yolları

    func testWriteFailureFailsSafe() async {
        let smc = FakeSMC.chte()
        smc.failWrites = true
        let rig = CoreRig(smc: smc, level: 90)
        await rig.core.start()
        let reply = await rig.core.handle(.setChargeLimit(enabled: true, limit: 80, sailingFloor: 75, topUp: false))
        XCTAssertFalse(reply.ok)
        XCTAssertEqual(reply.error, .smcFailure)
        XCTAssertFalse(rig.inhibited)
    }

    func testReadbackMismatchFailsSafe() async {
        let smc = FakeSMC.chte()
        smc.ignoreWrites = true
        let rig = CoreRig(smc: smc, level: 90)
        await rig.core.start()
        let reply = await rig.core.handle(.setChargeLimit(enabled: true, limit: 80, sailingFloor: 75, topUp: false))
        XCTAssertEqual(reply.status.lastError, .smcFailure)
        XCTAssertFalse(rig.inhibited)
    }

    // MARK: Komutlar

    func testResetAllRestoresEverything() async {
        let rig = CoreRig(smc: .chte(), level: 90, saved: limit80)
        await rig.core.start()
        _ = await rig.core.handle(.setMagSafeLED(.green))
        XCTAssertTrue(rig.inhibited)
        let reply = await rig.core.handle(.resetAll)
        XCTAssertTrue(reply.ok)
        XCTAssertFalse(rig.inhibited)
        XCTAssertEqual(rig.smc.value(.aclc), [0])
        XCTAssertEqual(rig.store.load(), HelperPersistedState(config: .off, ledMode: .auto))
        XCTAssertEqual(rig.scheduler.calls.last, false)
    }

    func testShutdownReleasesButKeepsConfig() async {
        let rig = CoreRig(smc: .chte(), level: 90, saved: limit80)
        await rig.core.start()
        XCTAssertTrue(rig.inhibited)
        await rig.core.shutdown()
        XCTAssertFalse(rig.inhibited)
        XCTAssertEqual(rig.store.load()?.config.enabled, true, "sonraki açılışta yeniden uygulanır")
    }

    func testTopUpFlow() async {
        let rig = CoreRig(smc: .chte(), level: 85, saved: limit80)
        await rig.core.start()
        XCTAssertTrue(rig.inhibited)
        _ = await rig.core.handle(.setChargeLimit(enabled: true, limit: 80, sailingFloor: 75, topUp: true))
        XCTAssertFalse(rig.inhibited, "tamamlarken engel kalkar")
        rig.battery.set(95); await rig.core.tick()
        XCTAssertFalse(rig.inhibited)
        rig.battery.set(100); await rig.core.tick()
        XCTAssertTrue(rig.inhibited, "dolunca sınır geri gelir")
        XCTAssertNil(rig.store.load()?.config.topUpStartedAt)
    }

    func testTopUpTimesOut() async {
        let rig = CoreRig(smc: .chte(), level: 85, saved: limit80)
        await rig.core.start()
        _ = await rig.core.handle(.setChargeLimit(enabled: true, limit: 80, sailingFloor: 75, topUp: true))
        rig.clock.advance(HelperConstants.topUpMaxSeconds + 60)
        await rig.core.tick()
        XCTAssertTrue(rig.inhibited)
    }

    func testManualInhibitHasTTLAndConflictsWithLimit() async {
        let rig = CoreRig(smc: .chte(), level: 60)
        await rig.core.start()
        let ok = await rig.core.handle(.setChargingInhibited(true, ttlSeconds: 120))
        XCTAssertTrue(ok.ok)
        XCTAssertTrue(rig.inhibited)
        XCTAssertEqual(rig.scheduler.calls, [true])
        rig.clock.advance(121); await rig.core.tick()
        XCTAssertFalse(rig.inhibited, "süre dolunca kendiliğinden kalkar")
        XCTAssertEqual(rig.scheduler.calls, [true, false])

        _ = await rig.core.handle(.setChargeLimit(enabled: true, limit: 80, sailingFloor: 75, topUp: false))
        let conflict = await rig.core.handle(.setChargingInhibited(true, ttlSeconds: 120))
        XCTAssertEqual(conflict.error, .conflictsWithLimit)
    }

    func testPollingOnlyWhileNeeded() async {
        let rig = CoreRig(smc: .chte(), level: 70)
        await rig.core.start()
        XCTAssertEqual(rig.scheduler.calls, [])
        _ = await rig.core.handle(.setChargeLimit(enabled: true, limit: 80, sailingFloor: 75, topUp: false))
        _ = await rig.core.handle(.setChargeLimit(enabled: false, limit: 80, sailingFloor: 75, topUp: false))
        XCTAssertEqual(rig.scheduler.calls, [true, false])
    }

    func testLowPowerModeAndFailure() async {
        let rig = CoreRig(smc: .thisMac())
        await rig.core.start()
        let on = await rig.core.handle(.setLowPowerMode(true))
        XCTAssertTrue(on.ok)
        XCTAssertTrue(on.status.lowPowerMode)
        rig.power.fail = true
        let failed = await rig.core.handle(.setLowPowerMode(false))
        XCTAssertEqual(failed.error, .pmsetFailure)
        XCTAssertTrue(rig.smc.writes.isEmpty)
    }

    func testLEDWriteAndPersistence() async {
        let rig = CoreRig(smc: .chte())
        await rig.core.start()
        let reply = await rig.core.handle(.setMagSafeLED(.green))
        XCTAssertTrue(reply.ok)
        XCTAssertEqual(rig.smc.value(.aclc), [3])
        XCTAssertEqual(rig.store.load()?.ledMode, .green)
        _ = await rig.core.handle(.setMagSafeLED(.auto))
        XCTAssertEqual(rig.smc.value(.aclc), [0])
    }

    func testRejectKeepsHardwareUntouched() async {
        let rig = CoreRig(smc: .chte(), level: 90)
        await rig.core.start()
        let reply = await rig.core.reject(.outOfRange)
        XCTAssertEqual(reply.error, .outOfRange)
        XCTAssertTrue(rig.smc.writes.isEmpty)
    }
}
