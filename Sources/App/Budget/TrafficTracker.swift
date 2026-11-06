import Foundation

/// Fiziksel arayüz deltalarının bellek içi izleyicisi: son dakikaların mobil hızı (tahmin için) ve
/// saatlik arayüz toplamları (grafik için; `UsageStore.addInterfaceHourly` ile yazılır). Sorgu yok.
@MainActor
final class TrafficTracker {
    private var ring = MinuteRing(capacity: 60)
    private var pending: [Int: (mobile: UInt64, other: UInt64)] = [:]
    private let startedAt: Date

    init(startedAt: Date = .now) { self.startedAt = startedAt }

    func add(bytes: UInt64, mobile: Bool, at now: Date) {
        guard bytes > 0 else { return }
        if mobile { ring.add(minute: Int(now.timeIntervalSince1970 / 60), total: bytes, mobile: bytes) }
        let hour = Int(now.timeIntervalSince1970) / 3600 * 3600
        var p = pending[hour] ?? (0, 0)
        if mobile { p.mobile &+= bytes } else { p.other &+= bytes }
        pending[hour] = p
    }

    /// Son `lastMinutes` dakikanın mobil hızı (B/sn). Uygulama yeni açıldıysa geçen süreye bölünür (en az 30 sn).
    func recentMobileRate(lastMinutes: Int = 15, now: Date) -> Double {
        let nowMinute = Int(now.timeIntervalSince1970 / 60)
        let sum = ring.sum(lastMinutes: lastMinutes, endingAt: nowMinute, mobileOnly: true)
        let intoMinute = now.timeIntervalSince1970 - Double(nowMinute * 60)
        let window = Double(max(1, lastMinutes) - 1) * 60 + intoMinute
        let seconds = max(30, min(window, now.timeIntervalSince(startedAt)))
        return Double(sum) / seconds
    }

    /// Henüz yazılmamış saatlik toplamları verir ve temizler.
    func drainHourly() -> [(hour: Int, mobile: UInt64, other: UInt64)] {
        let out = pending.map { (hour: $0.key, mobile: $0.value.mobile, other: $0.value.other) }.sorted { $0.hour < $1.hour }
        pending.removeAll(keepingCapacity: true)
        return out
    }
}
