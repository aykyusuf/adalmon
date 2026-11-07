import Foundation

/// XPC arayüzü. Yalnızca ilkel argümanlar; yanıtlar JSON `HelperReply`. Her yöntem yardımcıda yeniden doğrulanır.
@objc(AdalmonHelperProtocol)
protocol AdalmonHelperProtocol {
    func getStatus(reply: @escaping @Sendable (Data) -> Void)
    func setChargeLimit(enabled: Bool, limit: Int, sailingFloor: Int, topUp: Bool, reply: @escaping @Sendable (Data) -> Void)
    func setChargingInhibited(_ inhibited: Bool, ttlSeconds: Int, reply: @escaping @Sendable (Data) -> Void)
    func setLowPowerMode(_ enabled: Bool, reply: @escaping @Sendable (Data) -> Void)
    func setMagSafeLED(_ mode: Int, reply: @escaping @Sendable (Data) -> Void)
    func resetAll(reply: @escaping @Sendable (Data) -> Void)
}
