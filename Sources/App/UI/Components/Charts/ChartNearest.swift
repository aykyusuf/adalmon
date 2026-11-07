import Foundation

/// İmleç altındaki en yakın örneği bulur (saf mantık; ikili arama).
enum ChartNearest {
    /// `points` tarihe göre artan olmalı. `tolerance` verilirse ondan uzak noktalar sayılmaz (veri olmayan boş alan).
    static func index(in points: [ChartPoint], to date: Date, tolerance: TimeInterval? = nil) -> Int? {
        guard !points.isEmpty else { return nil }
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].date < date { low = mid + 1 } else { high = mid }
        }
        var best = low
        if low == points.count {
            best = points.count - 1
        } else if low > 0, date.timeIntervalSince(points[low - 1].date) <= points[low].date.timeIntervalSince(date) {
            best = low - 1
        }
        if let tolerance, abs(points[best].date.timeIntervalSince(date)) > tolerance { return nil }
        return best
    }

    /// Noktalar arası tipik aralığın 1,5 katı: bunun ötesindeki imleç "veri yok" sayılır.
    static func tolerance(for points: [ChartPoint]) -> TimeInterval? {
        guard points.count > 1, let first = points.first, let last = points.last else { return nil }
        let step = last.date.timeIntervalSince(first.date) / Double(points.count - 1)
        return max(step * 1.5, 0.5)
    }
}
