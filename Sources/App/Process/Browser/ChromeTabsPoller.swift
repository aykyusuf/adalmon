import Foundation

// MARK: Taşıma soyutlamaları (testlerde sahteleri kullanılır)

protocol CDPHTTPClient: Sendable {
    func get(_ url: URL) async throws -> Data
}

protocol CDPSocket: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close()
}

protocol CDPSocketFactory: Sendable {
    func connect(_ url: URL) -> any CDPSocket
}

enum CDPError: Error, Equatable {
    case timeout
    case closed
    case protocolError(String)
    case badEndpoint
}

/// Tek bir CDP bağlantısı (sekme ya da tarayıcı). Çağrılar sırayla yapılır; her çağrının zaman aşımı vardır (donmuş arka
/// plan sekmesi yoklamayı kilitlemesin). Zaman aşımında soket kapatılır ve bağlantı ölü sayılır.
actor CDPConnection {
    private let socket: any CDPSocket
    private var nextID = 1
    private(set) var isClosed = false

    init(socket: any CDPSocket) { self.socket = socket }

    func call(_ method: String, params: [String: String] = [:], timeout: Duration) async throws -> Data {
        guard !isClosed else { throw CDPError.closed }
        let id = nextID
        nextID += 1
        let socket = socket
        do {
            return try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await socket.send(CDPCodec.request(id: id, method: method, params: params))
                    while true {
                        try Task.checkCancellation()
                        let data = try await socket.receive()
                        guard let reply = CDPCodec.reply(from: data), reply.id == id else { continue }  // olaylar / eski yanıtlar
                        if let message = reply.errorMessage { throw CDPError.protocolError(message) }
                        return reply.result ?? Data("{}".utf8)
                    }
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    socket.close()  // bekleyen receive'i serbest bırakır
                    throw CDPError.timeout
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw CDPError.closed }
                return first
            }
        } catch let error as CDPError {
            if case .protocolError = error {} else { close() }
            throw error
        } catch {
            close()
            throw CDPError.closed
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        socket.close()
    }
}

// MARK: Yoklayıcı

struct ChromeTabSnapshot: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var url: String
    /// `Performance.getMetrics` alınamadıysa nil.
    var metrics: CDPTabMetrics?
}

struct ChromeSnapshot: Equatable, Sendable {
    var tabs: [ChromeTabSnapshot]
    /// `SystemInfo.getProcessInfo` (deneysel) desteklenmiyorsa nil.
    var processes: [CDPProcess]?
}

/// Hata ayıklama portundaki Chrome'u yoklar: `/json/list` → sekmeler; sekme başına kalıcı soketle `Performance.enable`
/// (bir kez) + `Performance.getMetrics`; tarayıcı soketinden `SystemInfo.getProcessInfo` (en iyi çaba).
/// Yalnızca 127.0.0.1 ve beklenen port; ws adresleri / belirteçler loglanmaz, hata metinlerine konmaz.
actor ChromeTabsPoller {
    static let maxTabs = 40
    let port: Int
    private let http: any CDPHTTPClient
    private let sockets: any CDPSocketFactory
    private let callTimeout: Duration
    private var tabConnections: [String: CDPConnection] = [:]
    private var browserConnection: CDPConnection?
    private var processInfoUnsupported = false

    init(port: Int, http: any CDPHTTPClient, sockets: any CDPSocketFactory, callTimeout: Duration = .seconds(2)) {
        self.port = port
        self.http = http
        self.sockets = sockets
        self.callTimeout = callTimeout
    }

    /// Liste alınamazsa (Chrome kapandı / port kapandı) hata fırlatır; sekme metriği alınamayan sekmede `metrics` nil.
    func poll() async throws -> ChromeSnapshot {
        guard let listURL = CDPEndpointGuard.httpURL(port: port, path: "/json/list") else { throw CDPError.badEndpoint }
        let targets = try CDPCodec.targets(from: try await http.get(listURL))
        // Tüm sekmeler listelenir; JS belleği yalnızca ilk `maxTabs` sekme için istenir (soket sayısı sınırlı).
        let measured = targets.prefix(Self.maxTabs)

        // Kaybolan sekmelerin soketleri kapanır.
        let alive = Set(measured.map(\.id))
        for (id, connection) in tabConnections where !alive.contains(id) {
            await connection.close()
            tabConnections[id] = nil
        }

        var jobs: [(String, CDPConnection, Bool)] = []
        for target in measured {
            if let existing = tabConnections[target.id], await !existing.isClosed {
                jobs.append((target.id, existing, false))
                continue
            }
            guard let raw = target.webSocketDebuggerUrl, let url = URL(string: raw), CDPEndpointGuard.isAllowed(url, port: port) else { continue }
            let connection = CDPConnection(socket: sockets.connect(url))
            tabConnections[target.id] = connection
            jobs.append((target.id, connection, true))
        }

        let timeout = callTimeout
        var metrics: [String: CDPTabMetrics] = [:]
        await withTaskGroup(of: (String, CDPTabMetrics?).self) { group in
            for (id, connection, isNew) in jobs {
                group.addTask {
                    do {
                        if isNew { _ = try await connection.call("Performance.enable", timeout: timeout) }
                        let result = try await connection.call("Performance.getMetrics", timeout: timeout)
                        return (id, CDPCodec.metrics(from: result))
                    } catch {
                        return (id, nil)
                    }
                }
            }
            for await (id, value) in group { if let value { metrics[id] = value } }
        }
        for (id, connection) in tabConnections {
            if await connection.isClosed { tabConnections[id] = nil }
        }

        let tabs = targets.map { ChromeTabSnapshot(id: $0.id, title: $0.title, url: $0.url, metrics: metrics[$0.id]) }
        return ChromeSnapshot(tabs: tabs, processes: await processInfo())
    }

    private func processInfo() async -> [CDPProcess]? {
        guard !processInfoUnsupported else { return nil }
        do {
            let connection: CDPConnection
            if let existing = browserConnection, await !existing.isClosed {
                connection = existing
            } else {
                guard let versionURL = CDPEndpointGuard.httpURL(port: port, path: "/json/version") else { return nil }
                let version = try CDPCodec.version(from: try await http.get(versionURL))
                guard let raw = version.webSocketDebuggerUrl, let url = URL(string: raw), CDPEndpointGuard.isAllowed(url, port: port) else { return nil }
                connection = CDPConnection(socket: sockets.connect(url))
                browserConnection = connection
            }
            return CDPCodec.processes(from: try await connection.call("SystemInfo.getProcessInfo", timeout: callTimeout))
        } catch CDPError.protocolError {
            // Deneysel alan bu sürümde yok: bir daha denenmez.
            processInfoUnsupported = true
            return nil
        } catch {
            return nil
        }
    }

    /// Bölüm kapanınca / bağlantı kopunca tüm soketler kapanır (Chrome ayrılan istemcinin Performance alanını kapatır).
    func shutdown() async {
        for connection in tabConnections.values { await connection.close() }
        tabConnections = [:]
        await browserConnection?.close()
        browserConnection = nil
    }

    var openConnectionCount: Int { tabConnections.count + (browserConnection == nil ? 0 : 1) }
}

// MARK: Gerçek taşıma (URLSession; yalnızca uygulamada)

/// Geçici (çerezsiz, önbelleksiz) oturum; yalnızca 127.0.0.1 adreslerine kullanılır.
final class URLSessionCDPTransport: CDPHTTPClient, CDPSocketFactory, @unchecked Sendable {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.connectionProxyDictionary = [:]  // yerel porta proxy üzerinden gidilmez
        session = URLSession(configuration: config)
    }

    func get(_ url: URL) async throws -> Data {
        guard CDPEndpointGuard.isAllowed(url, port: url.port ?? -1, schemes: ["http"]) else { throw CDPError.badEndpoint }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CDPError.closed }
        return data
    }

    func connect(_ url: URL) -> any CDPSocket {
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 4 * 1_024 * 1_024
        task.resume()
        return URLSessionCDPSocket(task: task)
    }

    deinit { session.invalidateAndCancel() }
}

final class URLSessionCDPSocket: CDPSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) { self.task = task }

    func send(_ data: Data) async throws {
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    func receive() async throws -> Data {
        switch try await task.receive() {
        case .string(let text): return Data(text.utf8)
        case .data(let data): return data
        @unknown default: throw CDPError.closed
        }
    }

    func close() { task.cancel(with: .normalClosure, reason: nil) }
}
