import Foundation
import Synchronization

enum ChargeHelperError: Error, Equatable, Sendable {
    case unreachable
    case timedOut
    case badReply
}

/// Yardımcıya komut gönderen istemci. Gerçeği XPC; testlerde sahte.
protocol ChargeHelperClienting: Sendable {
    func send(_ command: HelperCommand) async -> Result<HelperReply, ChargeHelperError>
    /// Uygulama kapanırken (ana iş parçacığını en çok `timeout` sn bloklar).
    func sendBlocking(_ command: HelperCommand, timeout: TimeInterval) -> Result<HelperReply, ChargeHelperError>
}

/// Her komut için kısa ömürlü bağlantı. Servisin gerçekten bizim yardımcımız olduğu `helperRequirement` ile doğrulanır.
final class XPCChargeHelperClient: ChargeHelperClienting {
    static let timeout: TimeInterval = 5

    func send(_ command: HelperCommand) async -> Result<HelperReply, ChargeHelperError> {
        await withCheckedContinuation { continuation in
            Self.dispatch(command, timeout: Self.timeout) { continuation.resume(returning: $0) }
        }
    }

    func sendBlocking(_ command: HelperCommand, timeout: TimeInterval) -> Result<HelperReply, ChargeHelperError> {
        let box = Mutex<Result<HelperReply, ChargeHelperError>>(.failure(.timedOut))
        let semaphore = DispatchSemaphore(value: 0)
        Self.dispatch(command, timeout: timeout) { result in
            box.withLock { $0 = result }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout + 0.5)
        return box.withLock { $0 }
    }

    // MARK: Bağlantı

    private final class ConnectionBox: @unchecked Sendable {
        let connection: NSXPCConnection
        init(_ connection: NSXPCConnection) { self.connection = connection }
    }

    /// Yanıtın tam bir kez teslim edilmesini sağlar.
    private final class Gate: Sendable {
        private let completion: Mutex<(@Sendable (Result<HelperReply, ChargeHelperError>) -> Void)?>
        private let box: ConnectionBox

        init(box: ConnectionBox, completion: @escaping @Sendable (Result<HelperReply, ChargeHelperError>) -> Void) {
            self.box = box
            self.completion = Mutex(completion)
        }

        func finish(_ result: Result<HelperReply, ChargeHelperError>) {
            let handler = completion.withLock { current -> (@Sendable (Result<HelperReply, ChargeHelperError>) -> Void)? in
                defer { current = nil }
                return current
            }
            guard let handler else { return }
            box.connection.invalidate()
            handler(result)
        }

        func finish(data: Data) {
            if let reply = HelperCoding.decode(HelperReply.self, from: data) { finish(.success(reply)) } else { finish(.failure(.badReply)) }
        }
    }

    private static func dispatch(_ command: HelperCommand, timeout: TimeInterval,
                                 completion: @escaping @Sendable (Result<HelperReply, ChargeHelperError>) -> Void) {
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.setCodeSigningRequirement(HelperConstants.helperRequirement)
        connection.remoteObjectInterface = NSXPCInterface(with: AdalmonHelperProtocol.self)
        let gate = Gate(box: ConnectionBox(connection), completion: completion)
        connection.invalidationHandler = { gate.finish(.failure(.unreachable)) }
        connection.interruptionHandler = { gate.finish(.failure(.unreachable)) }
        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in gate.finish(.failure(.unreachable)) }) as? AdalmonHelperProtocol else {
            gate.finish(.failure(.unreachable))
            return
        }
        let reply: @Sendable (Data) -> Void = { gate.finish(data: $0) }
        switch command {
        case .getStatus:
            proxy.getStatus(reply: reply)
        case let .setChargeLimit(enabled, limit, floor, topUp):
            proxy.setChargeLimit(enabled: enabled, limit: limit, sailingFloor: floor, topUp: topUp, reply: reply)
        case let .setChargingInhibited(inhibited, ttl):
            proxy.setChargingInhibited(inhibited, ttlSeconds: ttl, reply: reply)
        case let .setLowPowerMode(enabled):
            proxy.setLowPowerMode(enabled, reply: reply)
        case let .setMagSafeLED(mode):
            proxy.setMagSafeLED(mode.rawValue, reply: reply)
        case .resetAll:
            proxy.resetAll(reply: reply)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { gate.finish(.failure(.timedOut)) }
    }
}
