import Foundation
import Network

/// Yalnızca 127.0.0.1'de dinleyen yerel olay alıcısı (Network.framework). Olay yoksa hiçbir iş yapmaz (zamanlayıcı yok);
/// bağlantı başına 5 sn'lik tek seferlik zaman aşımı vardır. Token loga yazılmaz.
final class AgentEventServer: @unchecked Sendable {
    enum State: Equatable, Sendable {
        case stopped
        case running(port: UInt16)
        case failed(String)
    }

    static let portRange: ClosedRange<UInt16> = 49152...65000
    private static let maxConnections = 16
    private static let connectionTimeout: TimeInterval = 5

    private let queue = DispatchQueue(label: "adalmon.agents.server", qos: .utility)
    private let token: String
    private let onEvent: @Sendable (AgentEvent) -> Void
    private let onState: @Sendable (State) -> Void
    // Aşağıdakilere yalnızca `queue` üzerinden erişilir.
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var generation = 0

    init(token: String, onEvent: @escaping @Sendable (AgentEvent) -> Void, onState: @escaping @Sendable (State) -> Void) {
        self.token = token
        self.onEvent = onEvent
        self.onState = onState
    }

    static func randomPort() -> UInt16 { UInt16.random(in: portRange) }

    /// `preferredPort` doluysa birkaç kez yeni rastgele port dener; sonuç `onState` ile bildirilir.
    func start(preferredPort: UInt16?) {
        queue.async { [self] in
            stopLocked()
            generation += 1
            startLocked(port: preferredPort ?? Self.randomPort(), attemptsLeft: 8, generation: generation)
        }
    }

    func stop() {
        queue.async { [self] in
            generation += 1
            stopLocked()
            onState(.stopped)
        }
    }

    private func stopLocked() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections = [:]
    }

    private func startLocked(port: UInt16, attemptsLeft: Int, generation gen: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { onState(.failed("Geçersiz port")); return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do { listener = try NWListener(using: parameters) } catch {
            onState(.failed(error.localizedDescription))
            return
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            self.queue.async {
                guard self.generation == gen, self.listener === listener else { return }
                switch state {
                case .ready:
                    self.onState(.running(port: port))
                case .failed(let error):
                    listener.cancel()
                    self.listener = nil
                    if attemptsLeft > 0 {
                        self.startLocked(port: Self.randomPort(), attemptsLeft: attemptsLeft - 1, generation: gen)
                    } else {
                        self.onState(.failed(error.localizedDescription))
                    }
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.queue.async { self?.accept(connection) }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.maxConnections else { connection.cancel(); return }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async { self?.connections[id] = nil }
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.connectionTimeout) { connection.cancel() }
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            let outcome = AgentHTTPParser.parse(buffer, token: self.token)
            switch outcome {
            case .needMore:
                if error != nil || isComplete { connection.cancel() } else { self.receive(on: connection, buffer: buffer) }
            case .event(let event):
                self.onEvent(event)
                self.reply(outcome, on: connection)
            case .reject:
                self.reply(outcome, on: connection)
            }
        }
    }

    private func reply(_ outcome: AgentHTTPParser.Outcome, on connection: NWConnection) {
        connection.send(content: AgentHTTPParser.response(for: outcome), completion: .contentProcessed { _ in connection.cancel() })
    }
}
