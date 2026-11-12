import Foundation
import os

private let log = Logger(subsystem: AdalmonIdentity.appBundleID, category: "filter-link")

/// Filtre uzantısıyla konuşan taşıma katmanı (gerçekte XPC; testte sahte).
@MainActor
protocol FilterTransport: AnyObject {
    /// Her yeni bağlantı kurulduğunda artar. Uzantı yeniden başlamış olabileceği için yeni bağlantıya yapılandırma yeniden gönderilir.
    var generation: Int { get }
    /// Birikmiş kullanımı çeker; nil = bağlantı yok / cevap gelmedi / çözülemedi.
    func drain() async -> [UsageBucket]?
    func send(_ config: Data)
    /// Bağlantıyı bırakır; bir sonraki çağrı yenisini kurar.
    func reset()
}

/// Filtre system extension'ına istemci. Bağlantı koparsa geri çekilmeli olarak (2 → 4 → 8 → 16 → 30 sn) yeniden dener,
/// her yeni bağlantıda son yapılandırmayı hemen yeniden gönderir (yeniden başlayan uzantı boş yapılandırmayla kalmasın:
/// sınırlar/engeller uygulanmazdı). Zamanlayıcı yok; `drain` ölçüm adımından çağrılır.
@MainActor
final class FilterClient {
    private let transport: any FilterTransport
    private let now: () -> Date
    private(set) var isConnected = false
    private(set) var backoff = FilterBackoff()
    /// AppModel'in son verdiği yapılandırma (açılış durumu yüklenmeden hiç verilmez → o zamana kadar hiçbir şey gönderilmez).
    private(set) var lastConfig: FilterConfig?
    /// Yapılandırmanın en son teslim edildiği bağlantı.
    private var sentGeneration: Int?

    init(transport: (any FilterTransport)? = nil, now: @escaping () -> Date = { .now }) {
        self.transport = transport ?? XPCFilterTransport()
        self.now = now
    }

    /// Bağlantı ilk kez ne zaman koptu (bağlıyken nil).
    var disconnectedSince: Date? { backoff.failingSince }

    func drain() async -> [UsageBucket] {
        guard backoff.shouldAttempt(now: now()) else { return [] }
        guard let buckets = await transport.drain() else {
            isConnected = false
            transport.reset()
            let failures = backoff.failures + 1
            if backoff.recordFailure(now: now()) {
                log.warning("filtreye bağlanılamadı (art arda \(failures, privacy: .public). hata); \(Int(FilterBackoff.delay(afterFailures: failures)), privacy: .public) sn sonra yeniden denenecek")
            }
            return []
        }
        if backoff.failures > 0 {
            log.notice("filtre bağlantısı geri geldi (\(self.backoff.failures, privacy: .public) hatadan sonra)")
        }
        backoff.recordSuccess()
        isConnected = true
        // Yeni bağlantı = uzantı yeniden başlamış olabilir: yapılandırmayı hemen yeniden ver.
        if let lastConfig, sentGeneration != transport.generation {
            deliver(lastConfig)
            log.notice("yeni filtre bağlantısına yapılandırma yeniden gönderildi")
        }
        return buckets
    }

    func send(_ config: FilterConfig) {
        lastConfig = config
        // Bağlantı yokken bağlantı açılmaz (geri çekilme bozulmasın); bağlantı dönünce `drain` gönderir.
        guard backoff.failures == 0 else { return }
        deliver(config)
    }

    /// "Filtreyi yeniden bağla": yalnızca XPC bağlantısını yeniden kurar ve bekleme süresini atlar.
    /// Filtre ayarına (NEFilterManager) ve uzantıya dokunmaz.
    func reconnectNow() {
        transport.reset()
        backoff.allowImmediateAttempt()
    }

    private func deliver(_ config: FilterConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        transport.send(data)
        sentGeneration = transport.generation
    }
}

/// Gerçek XPC taşıması. Eski bağlantıdan gecikmeli gelen kopma/hata bildirimleri yalnızca kendi bağlantısını düşürür
/// (yeni kurulmuş bağlantıyı kapatıp yeniden kopmaya yol açmaz).
@MainActor
final class XPCFilterTransport: FilterTransport {
    private var connection: NSXPCConnection?
    private(set) var generation = 0

    private func proxy(onError: (@Sendable () -> Void)? = nil) -> FilterControl? {
        if connection == nil {
            generation += 1
            let gen = generation
            let c = NSXPCConnection(machServiceName: IPC.machServiceName, options: [])
            c.remoteObjectInterface = NSXPCInterface(with: FilterControl.self)
            c.invalidationHandler = { @Sendable [weak self] in Task { @MainActor in self?.drop(gen) } }
            c.interruptionHandler = { @Sendable [weak self] in Task { @MainActor in self?.drop(gen) } }
            c.resume()
            connection = c
        }
        let gen = generation
        return connection?.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in
            onError?()
            Task { @MainActor in self?.drop(gen) }
        } as? FilterControl
    }

    private func drop(_ gen: Int) {
        guard gen == generation else { return }
        reset()
    }

    func reset() {
        let c = connection
        connection = nil
        c?.invalidate()
    }

    func drain() async -> [UsageBucket]? {
        let once = OnceFlag()
        // JSON çözümü XPC cevap kuyruğunda yapılır (ana iş parçacığını meşgul etmez).
        return await withCheckedContinuation { (cont: CheckedContinuation<[UsageBucket]?, Never>) in
            // Zaman aşımı cevap gelince iptal edilir: her adımda boşa uyanan 2 sn'lik bir zamanlayıcı kalmaz (pil).
            nonisolated(unsafe) let timeout = DispatchWorkItem { @Sendable in if once.claim() { cont.resume(returning: nil) } }
            // Bağlantı hatası (ör. `bootstrap look-up ... No such process`) 2 sn beklemeden sonuçlanır.
            guard let p = proxy(onError: { if once.claim() { timeout.cancel(); cont.resume(returning: nil) } }) else {
                if once.claim() { cont.resume(returning: nil) }
                return
            }
            p.drainUsage { @Sendable data in
                guard once.claim() else { return }
                timeout.cancel()
                cont.resume(returning: data.isEmpty ? nil : try? JSONDecoder().decode([UsageBucket].self, from: data))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: timeout)
        }
    }

    func send(_ config: Data) {
        proxy()?.updateConfig(config) { @Sendable _ in }
    }
}

/// Continuation'ın tek sefer resume edilmesi için.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}
