import Foundation

/// Akış başına kümülatif rapor sayılarını deltaya çevirir ve dakikalık kovalarda biriktirir.
/// Uygulama kapalıyken de birikir; sınır aşılırsa en eski dakikalar atılır.
final class UsageAccumulator: @unchecked Sendable {
    struct FlowState {
        var app: String
        var signingID: String
        var host: String
        var kind: FlowKind
        var lastIn: UInt64 = 0
        var lastOut: UInt64 = 0
        var lastSeen: Date = .now
    }

    private let lock = NSLock()
    private var flows: [UUID: FlowState] = [:]
    private var buckets: [UsageBucket.Key: UsageBucket] = [:]
    private let maxBuckets = 50_000

    func begin(flow id: UUID, state: FlowState) {
        lock.withLock { flows[id] = state }
    }

    func setHost(_ host: String, for id: UUID) {
        lock.withLock { flows[id]?.host = host }
    }

    func state(for id: UUID) -> FlowState? {
        lock.withLock { flows[id] }
    }

    /// Kümülatif sayıları işler. `closed` ise akış unutulur.
    func report(flow id: UUID, totalIn: UInt64, totalOut: UInt64, expensive: Bool, closed: Bool) {
        lock.withLock {
            guard var f = flows[id] else { return }
            let dIn = totalIn >= f.lastIn ? totalIn - f.lastIn : 0
            let dOut = totalOut >= f.lastOut ? totalOut - f.lastOut : 0
            f.lastIn = max(f.lastIn, totalIn)
            f.lastOut = max(f.lastOut, totalOut)
            f.lastSeen = .now
            if closed { flows[id] = nil } else { flows[id] = f }
            guard dIn > 0 || dOut > 0 else { return }

            let minute = Int(Date.now.timeIntervalSince1970 / 60)
            let key = UsageBucket.Key(app: f.app, signingID: f.signingID, host: f.host, kind: f.kind, expensive: expensive, minute: minute)
            if var b = buckets[key] {
                b.bytesIn += dIn
                b.bytesOut += dOut
                buckets[key] = b
            } else {
                buckets[key] = UsageBucket(app: f.app, signingID: f.signingID, host: f.host, kind: f.kind,
                                           expensive: expensive, minute: minute, bytesIn: dIn, bytesOut: dOut)
                if buckets.count > maxBuckets { evictOldest() }
            }
        }
    }

    /// Biriken kovaları verir ve temizler.
    func drain() -> [UsageBucket] {
        lock.withLock {
            let out = Array(buckets.values)
            buckets.removeAll(keepingCapacity: true)
            sweepStaleFlows()
            return out
        }
    }

    /// Kapanış raporu gelmeyen akışlar için TTL temizliği (lock altında çağrılır).
    private func sweepStaleFlows() {
        let cutoff = Date.now.addingTimeInterval(-6 * 3600)
        flows = flows.filter { $0.value.lastSeen > cutoff }
    }

    private func evictOldest() {
        guard let oldest = buckets.keys.map(\.minute).min() else { return }
        buckets = buckets.filter { $0.key.minute != oldest }
    }
}
