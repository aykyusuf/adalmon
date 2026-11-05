import Foundation

/// Uygulama × yön başına paylaşılan token kovaları. Bir uygulamanın tüm akışları aynı kovayı tüketir.
/// Sınır her ayırmada güncel ayardan okunur: sınır kaldırılınca açık akışlar da hemen tam hıza döner.
final class RateLimiter: @unchecked Sendable {
    static let shared = RateLimiter()

    private struct Key: Hashable { let app: String; let down: Bool }
    private let lock = NSLock()
    private var buckets: [Key: TokenBucket] = [:]

    private static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }

    /// `bytes` aktarılmadan önce beklenecek süre (sn). Sınır yoksa 0.
    func delay(app: String, direction: ThrottleDirection, bytes: Int) -> Double {
        let server = XPCServer.shared
        guard let limit = ThrottlePolicy.activeLimit(app: app, config: server.config, expensive: server.isExpensive),
              let rate = limit.rate(direction) else { return 0 }
        let key = Key(app: app, down: direction == .down)
        let now = Self.now()
        return lock.withLock {
            var b = buckets[key] ?? TokenBucket(bytesPerSecond: rate, now: now)
            b.setRate(rate)
            let d = b.reserve(bytes, now: now)
            buckets[key] = b
            return d
        }
    }

    /// Okuma parçası: düşük hızlarda daha küçük parça = daha düzgün akış. 4 KB … 64 KB.
    func chunkSize(app: String, direction: ThrottleDirection) -> Int {
        let server = XPCServer.shared
        guard let limit = ThrottlePolicy.activeLimit(app: app, config: server.config, expensive: server.isExpensive),
              let rate = limit.rate(direction) else { return 64 * 1024 }
        return min(64 * 1024, max(4 * 1024, rate / 8))
    }
}
