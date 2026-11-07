import Foundation
@testable import Adalmon

/// Sahte SMC: gerçek AppleSMC'ye ASLA dokunmaz. Yazmalar kaydedilir.
final class FakeSMC: SMCAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var descriptors: [SMCKey: SMCKeyDescriptor]
    private var values: [SMCKey: [UInt8]]
    private var recorded: [SMCWrite] = []
    var failWrites = false
    /// Yazmaları kabul edip değeri DEĞİŞTİRME (geri okuma uyuşmazlığı).
    var ignoreWrites = false

    init(descriptors: [SMCKey: SMCKeyDescriptor], values: [SMCKey: [UInt8]]) {
        self.descriptors = descriptors
        self.values = values
    }

    /// Bu Mac'te okunan gerçek durum: yalnızca ACLC var (CHTE/CH0B/CH0C yok).
    static func thisMac() -> FakeSMC {
        FakeSMC(descriptors: [.aclc: .init(size: 1, dataType: "ui8 ")], values: [.aclc: [3]])
    }

    static func chte(inhibited: Bool = false, withLED: Bool = true) -> FakeSMC {
        var d: [SMCKey: SMCKeyDescriptor] = [.chte: .init(size: 4, dataType: "hex_")]
        var v: [SMCKey: [UInt8]] = [.chte: inhibited ? [1, 0, 0, 0] : [0, 0, 0, 0]]
        if withLED { d[.aclc] = .init(size: 1, dataType: "ui8 "); v[.aclc] = [0] }
        return FakeSMC(descriptors: d, values: v)
    }

    static func legacy(inhibited: Bool = false) -> FakeSMC {
        FakeSMC(descriptors: [.ch0b: .init(size: 1, dataType: "hex_"), .ch0c: .init(size: 1, dataType: "hex_")],
                values: [.ch0b: [inhibited ? 2 : 0], .ch0c: [inhibited ? 2 : 0]])
    }

    var writes: [SMCWrite] { lock.lock(); defer { lock.unlock() }; return recorded }
    func value(_ key: SMCKey) -> [UInt8]? { lock.lock(); defer { lock.unlock() }; return values[key] }

    func descriptor(of key: SMCKey) -> SMCKeyDescriptor? { lock.lock(); defer { lock.unlock() }; return descriptors[key] }
    func read(_ key: SMCKey) -> [UInt8]? { lock.lock(); defer { lock.unlock() }; return values[key] }

    func write(_ write: SMCWrite) -> Bool {
        guard SMCWriteAllowlist.permits(write) else { return false }
        lock.lock(); defer { lock.unlock() }
        guard let d = descriptors[write.key], d.size == write.bytes.count else { return false }
        recorded.append(write)
        if failWrites { return false }
        if !ignoreWrites { values[write.key] = write.bytes }
        return true
    }
}

final class FakeBattery: BatteryProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: BatterySnapshot?

    init(level: Int, plugged: Bool = true) { current = Self.make(level, plugged) }

    static func make(_ level: Int, _ plugged: Bool) -> BatterySnapshot {
        BatterySnapshot(level: level, isPluggedIn: plugged, isCharging: plugged && level < 100, isFullyCharged: level >= 100)
    }

    func set(_ level: Int, plugged: Bool = true) { lock.lock(); current = Self.make(level, plugged); lock.unlock() }
    func clear() { lock.lock(); current = nil; lock.unlock() }
    func snapshot() -> BatterySnapshot? { lock.lock(); defer { lock.unlock() }; return current }
}

final class FakePower: PowerSettingApplying, @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    var fail = false
    func setLowPowerMode(_ enabled: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fail { return false }
        on = enabled
        return true
    }
    func isLowPowerModeEnabled() -> Bool { lock.lock(); defer { lock.unlock() }; return on }
}

final class FakeStore: HelperStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: HelperPersistedState?
    init(_ state: HelperPersistedState? = nil) { self.state = state }
    func load() -> HelperPersistedState? { lock.lock(); defer { lock.unlock() }; return state }
    func save(_ state: HelperPersistedState) { lock.lock(); self.state = state; lock.unlock() }
}

final class FakeScheduler: PollScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var history: [Bool] = []
    func setPolling(_ active: Bool) { lock.lock(); history.append(active); lock.unlock() }
    var calls: [Bool] { lock.lock(); defer { lock.unlock() }; return history }
}

final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); date = date.addingTimeInterval(seconds); lock.unlock() }
}

/// Çekirdek + sahteler.
struct CoreRig {
    let core: HelperCore
    let smc: FakeSMC
    let battery: FakeBattery
    let power: FakePower
    let store: FakeStore
    let scheduler: FakeScheduler
    let clock: FakeClock

    init(smc: FakeSMC, level: Int = 70, plugged: Bool = true, saved: HelperPersistedState? = nil) {
        let clock = FakeClock()
        self.smc = smc
        battery = FakeBattery(level: level, plugged: plugged)
        power = FakePower()
        store = FakeStore(saved)
        scheduler = FakeScheduler()
        self.clock = clock
        core = HelperCore(smc: smc, battery: battery, power: power, store: store, scheduler: scheduler, clock: { clock.now })
    }

    var inhibited: Bool { smc.value(.chte) == [1, 0, 0, 0] }
}
