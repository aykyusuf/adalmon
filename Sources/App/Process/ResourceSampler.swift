import Foundation

/// Arka planda dakikada bir tüm coalition'ları süpürür, farkları ilk-15 birleşimine indirip SQLite'a yazar.
/// Utility QoS kuyruğu, geniş zamanlayıcı toleransı (pil). Başka hiçbir şeyi (süreç ayrıntısı, GPU istemcileri) örneklemez.
final class ResourceSampler: @unchecked Sendable {
    static let interval: TimeInterval = 60
    static let leeway: TimeInterval = 15

    private let queue = DispatchQueue(label: "adalmon.resources", qos: .utility)
    private let sweeper = ResourceSweeper()
    private let store: UsageStore
    private let sink: @Sendable (UInt64) -> Void
    private var timer: DispatchSourceTimer?
    private var sweepCount = 0
    private var importantFree: UInt64 = 0

    /// - Parameter writeSink: her süpürmede sistemin toplam disk yazma baytı (klasör taraması "boşta mı" kararı için).
    init(store: UsageStore, writeSink: @escaping @Sendable (UInt64) -> Void = { _ in }) {
        self.store = store
        self.sink = writeSink
    }

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .seconds(Int(Self.leeway)))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
            // Taban çizgisi şimdi alınır (ilk dakikalık kayıt ~65 sn sonra).
            _ = sweeper.sweep()
            Task { await store.resourceMaintenance() }
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    /// Bir süpürme + kayıt (kuyrukta çalışır). Testler ve ölçüm için doğrudan çağrılabilir.
    func tick(now: Date = .now) {
        let result = sweeper.sweep()
        sweepCount += 1
        let items = result.groups.map { KeyedUsage(key: $0.key, usage: $0.value.usage) }
        let rows = TopNUnion.select(items)
        sink(result.totalWriteBytes)
        if sweepCount % 10 == 1, let v = VolumeSpace.importantFreeBytes() { importantFree = v }
        let ts = Int(now.timeIntervalSince1970) / 60 * 60
        let free = VolumeSpace.freeBytes()
        let important = importantFree
        let doMaintenance = sweepCount % 60 == 0
        Task.detached(priority: .utility) { [store] in
            await store.addResourceMinute(ts: ts, rows: rows, freeBytes: free, importantFreeBytes: important)
            if doMaintenance { await store.resourceMaintenance(now: now) }
        }
    }

    /// Ölçüm/test: kuyrukta tek bir süpürme çalıştırıp bitmesini bekler.
    func tickNowAndWait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                tick()
                c.resume()
            }
        }
    }
}
