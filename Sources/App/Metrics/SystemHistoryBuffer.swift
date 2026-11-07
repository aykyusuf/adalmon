import Foundation
import Observation

/// Sistem metriklerinin bellek içi halka tamponu (CPU, bellek, GPU, disk, ağ). `AppModel` her ölçüm adımında zaten
/// aldığı değerleri buraya yazar; ek örnekleme yoktur. Performans sekmesi açılır açılmaz son dakikaları buradan çizer.
/// Yalnızca sayı tutar (~600 × 72 bayt); gözlem yalnızca `revision` üzerinden, ana pencere görünürken artar (pil).
@MainActor @Observable
final class SystemHistoryBuffer {
    static let capacity = 600

    /// Görünür pencere için her yeni örnekte artar; gizliyken artmaz (görünümler boşuna yeniden çizilmez).
    private(set) var revision = 0

    @ObservationIgnored private var ring: [SystemSample] = []
    /// Dolu halkada bir sonra yazılacak (= en eski) indeks.
    @ObservationIgnored private var head = 0
    @ObservationIgnored private let capacity: Int

    init(capacity: Int = SystemHistoryBuffer.capacity) {
        self.capacity = max(2, capacity)
        ring.reserveCapacity(self.capacity)
    }

    var count: Int { ring.count }

    /// En yeni örneğin zamanı.
    var latestTime: Date? { ordered(last: 1).last?.time }

    /// Aynı zaman damgalı örnek iki kez yazılmaz. `notify` false ise görünümler uyandırılmaz.
    func append(_ s: SystemSnapshot, notify: Bool) {
        append(SystemSample(s), notify: notify)
    }

    func append(_ sample: SystemSample, notify: Bool) {
        if let last = ordered(last: 1).last, last.time >= sample.time { return }
        if ring.count < capacity {
            ring.append(sample)
        } else {
            ring[head] = sample
            head = (head + 1) % capacity
        }
        if notify { revision &+= 1 }
    }

    /// Eskiden yeniye sıralı örnekler; `window` verilirse son `window` saniyedekiler (en yeni örneğe göre).
    func samples(window: TimeInterval? = nil) -> [SystemSample] {
        let all = ordered(last: ring.count)
        guard let window, let newest = all.last?.time else { return all }
        let cutoff = newest.addingTimeInterval(-window)
        let start = all.firstIndex { $0.time >= cutoff } ?? all.count
        return Array(all[start...])
    }

    /// Son `n` örneğin tek sayı değerleri (kutucuk spark çizgileri).
    func recentValues(_ metric: PerformanceMetric, count n: Int) -> [Double] {
        ordered(last: n).map { $0.value(metric) }
    }

    /// Tüm geçmişi siler (testler).
    func removeAll() {
        ring.removeAll(keepingCapacity: true)
        head = 0
    }

    private func ordered(last n: Int) -> [SystemSample] {
        let total = ring.count
        let take = min(max(0, n), total)
        guard take > 0 else { return [] }
        var out: [SystemSample] = []
        out.reserveCapacity(take)
        // Mantıksal sıra: head'den başlayıp dolaşır (dolu değilken head = 0).
        for i in (total - take)..<total { out.append(ring[(head + i) % total]) }
        return out
    }
}
