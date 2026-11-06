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
        // JSON çözümü XPC cevap kuyruğunda yapılır (ana iş parçacığını meşgul etmez); nil = bağlantı yok/boş cevap.
        let buckets: [UsageBucket]? = await withCheckedContinuation { cont in
            let once = OnceFlag()
            // Zaman aşımı cevap gelince iptal edilir: her adımda boşa uyanan 2 sn'lik bir zamanlayıcı kalmaz (pil).
            nonisolated(unsafe) let timeout = DispatchWorkItem { @Sendable in if once.claim() { cont.resume(returning: nil) } }
            p.drainUsage { @Sendable data in
                guard once.claim() else { return }
                timeout.cancel()
                cont.resume(returning: data.isEmpty ? nil : try? JSONDecoder().decode([UsageBucket].self, from: data))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: timeout)
        }
        guard let buckets else {
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
