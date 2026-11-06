import Foundation

/// Dakika başına sayaç halkası (toplam ve mobil byte). Her yuva kendi dakikasını taşır; böylece boşluklar,
/// geç gelen kovalar ve saat sıçramaları sıfırlama mantığı gerektirmeden doğru toplanır.
struct MinuteRing: Sendable, Equatable {
    struct Slot: Sendable, Equatable {
        var minute = Int.min
        var total: UInt64 = 0
        var mobile: UInt64 = 0
    }

    private(set) var slots: [Slot]
    var capacity: Int { slots.count }

    init(capacity: Int) {
        slots = Array(repeating: Slot(), count: max(1, capacity))
    }

    private func index(_ minute: Int) -> Int {
        ((minute % slots.count) + slots.count) % slots.count
    }

    /// `minute` (epoch/60) yuvasına ekler. Yuva daha yeni bir dakikaya devredilmişse (çok eski kova) yok sayılır.
    mutating func add(minute: Int, total: UInt64, mobile: UInt64) {
        let i = index(minute)
        if slots[i].minute < minute { slots[i] = Slot(minute: minute) }
        guard slots[i].minute == minute else { return }
        slots[i].total &+= total
        slots[i].mobile &+= mobile
    }

    /// `minute` dahil geriye doğru `n` dakikanın toplamı (n kapasiteye sıkıştırılır).
    func sum(lastMinutes n: Int, endingAt minute: Int, mobileOnly: Bool) -> UInt64 {
        var result: UInt64 = 0
        for k in 0..<min(max(0, n), slots.count) {
            let m = minute - k
            let s = slots[index(m)]
            guard s.minute == m else { continue }
            result &+= mobileOnly ? s.mobile : s.total
        }
        return result
    }
}
