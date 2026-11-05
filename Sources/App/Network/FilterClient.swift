import Foundation

/// Filtre system extension'ına XPC istemcisi. Bağlantı koparsa bir sonraki çağrıda yeniden kurulur.
@MainActor
final class FilterClient {
    private var connection: NSXPCConnection?
    private(set) var isConnected = false

    private func proxy() -> FilterControl? {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: IPC.machServiceName, options: [])
            c.remoteObjectInterface = NSXPCInterface(with: FilterControl.self)
            c.invalidationHandler = { @Sendable [weak self] in Task { @MainActor in self?.reset() } }
            c.interruptionHandler = { @Sendable [weak self] in Task { @MainActor in self?.reset() } }
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in
            Task { @MainActor in self?.reset() }
        } as? FilterControl
    }

    private func reset() {
        connection?.invalidate()
        connection = nil
        isConnected = false
    }

    func drain() async -> [UsageBucket] {
        guard let p = proxy() else { return [] }
        let data: Data = await withCheckedContinuation { cont in
            let once = OnceFlag()
            p.drainUsage { @Sendable data in if once.claim() { cont.resume(returning: data) } }
            // XPC hata işleyicisi cevap çağırmazsa takılmayalım.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { @Sendable in if once.claim() { cont.resume(returning: Data()) } }
        }
        guard !data.isEmpty, let buckets = try? JSONDecoder().decode([UsageBucket].self, from: data) else {
            isConnected = false
            return []
        }
        isConnected = true
        return buckets
    }

    func send(_ config: FilterConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        proxy()?.updateConfig(data) { @Sendable _ in }
    }
}

/// Continuation'ın tek sefer resume edilmesi için.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}
