import Foundation
import Network

/// Yalnızca 127.0.0.1'de dinleyen yerel olay alıcısı (Network.framework). Olay yoksa hiçbir iş yapmaz (zamanlayıcı yok);
/// bağlantı başına 5 sn'lik tek seferlik zaman aşımı vardır. Token loga yazılmaz.
/// Tarayıcı görünümü (`AgentWebStore` verilmişse): aynı dinleyicide GET/HEAD (sayfa, varlık, durum, SSE). SSE bağlantıları zaman
/// aşımından muaftır; yalnızca istemci varken 15 sn'lik bir keep-alive zamanlayıcısı çalışır (istemci yoksa zamanlayıcı yok).
/// Ofisten cevapla (`POST /v1/decision`): bağlantı kullanıcı karar verene dek TUTULUR; tutulan bağlantılar `maxConnections`'a sayılmaz,
/// kendi üst sınırları (`maxHeld`) vardır ve 5 sn'lik zaman aşımından muaftır (olay iletici bu yüzden aç kalmaz). Zamanlayıcı yok:
/// bağlantı kapanışı yalnızca okuma geri çağrısıyla fark edilir.
final class AgentEventServer: @unchecked Sendable {
    enum State: Equatable, Sendable {
        case stopped
        case running(port: UInt16)
        case failed(String)
    }

    static let portRange: ClosedRange<UInt16> = 49152...65000
    private static let maxConnections = 16
    static let maxHeld = PendingDecisionStore.maxPending
    private static let connectionTimeout: TimeInterval = 5

    private let queue = DispatchQueue(label: "adalmon.agents.server", qos: .utility)
    private let token: String
    private let web: AgentWebStore?
    private let keepAliveInterval: TimeInterval
    private let onEvent: @Sendable (AgentEvent) -> Void
    private let onState: @Sendable (State) -> Void
    private let onLimits: @Sendable (ClaudeLimitsMessage) -> Void
    private let onDecision: @Sendable (DecisionRequest, UUID) -> Void
    private let onHeldClosed: @Sendable (UUID) -> Void
    // Aşağıdakilere yalnızca `queue` üzerinden erişilir.
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var generation = 0
    private var port: UInt16 = 0
    private var sseClients: [ObjectIdentifier: NWConnection] = [:]
    private var keepAlive: DispatchSourceTimer?
    private var held: [UUID: NWConnection] = [:]
    private var heldIDs: [ObjectIdentifier: UUID] = [:]
    /// SSE istemci sayısı değişince (queue üzerinden) çağrılır: arka plan işlemi gözlemci sayacını sürer. Başlatmadan önce atanır.
    var onStreamCount: (@Sendable (Int) -> Void)?
    private var reportedStreams = 0

    private func reportStreams() {
        guard sseClients.count != reportedStreams else { return }
        reportedStreams = sseClients.count
        onStreamCount?(reportedStreams)
    }

    init(token: String, web: AgentWebStore? = nil, keepAliveInterval: TimeInterval = 15,
         onEvent: @escaping @Sendable (AgentEvent) -> Void, onState: @escaping @Sendable (State) -> Void,
         onLimits: @escaping @Sendable (ClaudeLimitsMessage) -> Void = { _ in },
         onDecision: @escaping @Sendable (DecisionRequest, UUID) -> Void = { _, _ in },
         onHeldClosed: @escaping @Sendable (UUID) -> Void = { _ in }) {
        self.token = token
        self.web = web
        self.keepAliveInterval = keepAliveInterval
        self.onEvent = onEvent
        self.onState = onState
        self.onLimits = onLimits
        self.onDecision = onDecision
        self.onHeldClosed = onHeldClosed
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
        for connection in held.values { connection.cancel() }
        held = [:]
        heldIDs = [:]
        sseClients = [:]
        reportStreams()
        keepAlive?.cancel()
        keepAlive = nil
    }

    /// Bağlı tüm SSE istemcilerine yeni anlık görüntüyü yollar (yalnızca durum değişince çağrılır; istemci yoksa iş yok).
    func broadcast(_ json: Data) {
        queue.async { [self] in
            guard !sseClients.isEmpty else { return }
            let frame = AgentWebRouter.sseEvent(json)
            for connection in sseClients.values { send(frame, on: connection) }
        }
    }

    /// Tarayıcı görünümü kapanınca açık akışları keser.
    func closeStreams() {
        queue.async { [self] in
            for connection in sseClients.values { connection.cancel() }
            sseClients = [:]
            reportStreams()
            updateKeepAlive()
        }
    }

    /// Tutulan karar bağlantısına yanıt yazar ve kapatır (betik hemen çıkar). Kimlik yoksa (bağlantı zaten kapandı) hiçbir şey yapmaz.
    /// `response`: `AgentDecisionParser.response(for:)` / `response(status:)`.
    func respondHeld(_ id: UUID, response: Data) {
        queue.async { [self] in
            guard let connection = held.removeValue(forKey: id) else { return }
            heldIDs[ObjectIdentifier(connection)] = nil
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// Test/teşhis: tutulan karar bağlantısı sayısı.
    func heldCount() async -> Int {
        await withCheckedContinuation { continuation in queue.async { [self] in continuation.resume(returning: held.count) } }
    }

    /// Test/teşhis: bağlı SSE istemcisi sayısı.
    func sseClientCount() async -> Int {
        await withCheckedContinuation { continuation in queue.async { [self] in continuation.resume(returning: sseClients.count) } }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in if error != nil { connection.cancel() } })
    }

    private func updateKeepAlive() {
        if sseClients.isEmpty {
            keepAlive?.cancel()
            keepAlive = nil
            return
        }
        guard keepAlive == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + keepAliveInterval, repeating: keepAliveInterval, leeway: .milliseconds(Int(keepAliveInterval * 100)))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            for connection in self.sseClients.values { self.send(AgentWebRouter.sseKeepAlive, on: connection) }
        }
        timer.resume()
        keepAlive = timer
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
                    self.port = port
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
                self?.queue.async {
                    self?.connections[id] = nil
                    if self?.sseClients.removeValue(forKey: id) != nil { self?.updateKeepAlive(); self?.reportStreams() }
                    if let self, let held = self.heldIDs.removeValue(forKey: id) {
                        self.held[held] = nil
                        self.onHeldClosed(held)
                    }
                }
            default: break
            }
        }
        connection.start(queue: queue)
        // SSE'ye çevrilen bağlantı zaman aşımından muaftır.
        queue.asyncAfter(deadline: .now() + Self.connectionTimeout) { [weak self] in
            if self?.sseClients[id] == nil, self?.heldIDs[id] == nil { connection.cancel() }
        }
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if AgentDecisionParser.isDecisionRequest(buffer) {
                self.receiveDecision(on: connection, buffer: buffer, closed: error != nil || isComplete)
                return
            }
            if self.web != nil, AgentWebRouter.isWebRequest(buffer) {
                self.receiveWeb(on: connection, buffer: buffer, closed: error != nil || isComplete)
                return
            }
            let outcome = AgentHTTPParser.parse(buffer, token: self.token, port: self.port == 0 ? nil : self.port)
            switch outcome {
            case .needMore:
                if error != nil || isComplete { connection.cancel() } else { self.receive(on: connection, buffer: buffer) }
            case .event(let event):
                self.onEvent(event)
                self.reply(outcome, on: connection)
            case .limits(let limits):
                self.onLimits(limits)
                self.reply(outcome, on: connection)
            case .reject:
                self.reply(outcome, on: connection)
            }
        }
    }

    private func receiveDecision(on connection: NWConnection, buffer: Data, closed: Bool) {
        switch AgentDecisionParser.parse(buffer, token: token, port: port == 0 ? nil : port) {
        case .needMore:
            if closed { connection.cancel() } else { receive(on: connection, buffer: buffer) }
        case .reject(let status):
            connection.send(content: AgentDecisionParser.response(status: status), completion: .contentProcessed { _ in connection.cancel() })
        case .request(let request):
            guard held.count < Self.maxHeld else {
                connection.send(content: AgentDecisionParser.response(status: 429), completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            let id = UUID()
            let key = ObjectIdentifier(connection)
            connections[key] = nil // olay iletici bağlantı payından düşer; kapanış aşağıda stateUpdateHandler'dan izlenir
            held[id] = connection
            heldIDs[key] = id
            drain(connection)
            onDecision(request, id)
        }
    }

    private func receiveWeb(on connection: NWConnection, buffer: Data, closed: Bool) {
        guard let web else { return }
        switch AgentWebRouter.parse(buffer) {
        case .needMore:
            if closed { connection.cancel() } else { receive(on: connection, buffer: buffer) }
        case .reject(let status):
            let response = AgentWebRouter.Response(status: status, contentType: "text/plain; charset=utf-8",
                                                   body: Data("\(status) \(AgentWebRouter.reason(status))\n".utf8))
            connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
        case .request(let request):
            let context = web.context(token: token, port: port, sseClients: sseClients.count)
            switch AgentWebRouter.route(request, context: context) {
            case .response(let response):
                connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
            case .stream:
                startStream(connection, snapshot: context.stateJSON)
            }
        }
    }

    private func startStream(_ connection: NWConnection, snapshot: Data) {
        sseClients[ObjectIdentifier(connection)] = connection
        reportStreams()
        updateKeepAlive()
        // Bayat görüntü gönderilmez: istemci sayısı bildirimi ana aktörde taze görüntüyü üretip yayınlar.
        send(AgentWebRouter.sseOpening(web?.isStale == true ? nil : snapshot), on: connection)
        drain(connection)
    }

    /// İstemci kapanışını fark etmek için okur (gelen baytlar yok sayılır).
    private func drain(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, isComplete, error in
            if error != nil || isComplete { connection.cancel() } else { self?.drain(connection) }
        }
    }

    private func reply(_ outcome: AgentHTTPParser.Outcome, on connection: NWConnection) {
        connection.send(content: AgentHTTPParser.response(for: outcome), completion: .contentProcessed { _ in connection.cancel() })
    }
}
