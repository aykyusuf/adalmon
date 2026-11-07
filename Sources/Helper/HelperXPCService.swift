import Foundation

/// XPC uç noktası: her çağrı yardımcıda yeniden doğrulanır, sonra `HelperCore`'a gider.
final class HelperXPCService: NSObject, AdalmonHelperProtocol, @unchecked Sendable {
    private let core: HelperCore

    init(core: HelperCore) { self.core = core }

    func getStatus(reply: @escaping @Sendable (Data) -> Void) {
        run(.success(.getStatus), reply)
    }

    func setChargeLimit(enabled: Bool, limit: Int, sailingFloor: Int, topUp: Bool, reply: @escaping @Sendable (Data) -> Void) {
        run(HelperCommand.chargeLimit(enabled: enabled, limit: limit, sailingFloor: sailingFloor, topUp: topUp), reply)
    }

    func setChargingInhibited(_ inhibited: Bool, ttlSeconds: Int, reply: @escaping @Sendable (Data) -> Void) {
        run(HelperCommand.chargingInhibited(inhibited, ttlSeconds: ttlSeconds), reply)
    }

    func setLowPowerMode(_ enabled: Bool, reply: @escaping @Sendable (Data) -> Void) {
        run(.success(.setLowPowerMode(enabled)), reply)
    }

    func setMagSafeLED(_ mode: Int, reply: @escaping @Sendable (Data) -> Void) {
        run(HelperCommand.magSafeLED(rawValue: mode), reply)
    }

    func resetAll(reply: @escaping @Sendable (Data) -> Void) {
        run(.success(.resetAll), reply)
    }

    private func run(_ parsed: Result<HelperCommand, HelperErrorCode>, _ reply: @escaping @Sendable (Data) -> Void) {
        let core = core
        Task {
            switch parsed {
            case let .success(command): reply(HelperCoding.encode(await core.handle(command)))
            case let .failure(error): reply(HelperCoding.encode(await core.reject(error)))
            }
        }
    }
}
