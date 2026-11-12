import CoreGraphics
import Foundation

/// Düzenlenecek bir öğe: kimlik + ağırlık (bayt). Ağırlığı sıfır, negatif ya da sayı olmayan öğeler yerleşime girmez.
struct TreemapItem: Equatable, Sendable {
    var id: String
    var value: Double
}

struct TreemapRect: Equatable, Sendable {
    var id: String
    var rect: CGRect
}

/// Squarified treemap (Bruls, Huizing, van Wijk). Çıktı alanları girdi değerleriyle orantılıdır, üst üste binmez ve `bounds`
/// içinde kalır. Öğeler büyükten küçüğe sıralanır (eşitlikte girdi sırası korunur).
enum TreemapLayout {
    static func layout(_ items: [TreemapItem], in bounds: CGRect) -> [TreemapRect] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        let valid = items.enumerated().filter { $0.element.value.isFinite && $0.element.value > 0 }
            .sorted { $0.element.value != $1.element.value ? $0.element.value > $1.element.value : $0.offset < $1.offset }
            .map(\.element)
        guard !valid.isEmpty else { return [] }
        let total = valid.reduce(0) { $0 + $1.value }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = valid.map { $0.value * scale }

        var out: [TreemapRect] = []
        out.reserveCapacity(valid.count)
        var free = bounds
        var start = 0
        while start < valid.count {
            let side = Double(min(free.width, free.height))
            var end = start + 1
            var rowSum = areas[start]
            var best = worst(sum: rowSum, minArea: areas[start], maxArea: areas[start], side: side)
            while end < valid.count {
                let area = areas[end]
                let newSum = rowSum + area
                // Satır içinde alanlar azalan sırada: en büyük başta, en küçük sonda.
                let candidate = worst(sum: newSum, minArea: area, maxArea: areas[start], side: side)
                if candidate > best { break }
                best = candidate
                rowSum = newSum
                end += 1
            }
            free = place(row: start..<end, items: valid, areas: areas, rowSum: rowSum, free: free, into: &out, isLast: end == valid.count)
            start = end
        }
        return out
    }

    /// Satırdaki en kötü en-boy oranı (1'e yakın iyi).
    private static func worst(sum: Double, minArea: Double, maxArea: Double, side: Double) -> Double {
        guard sum > 0, minArea > 0, side > 0 else { return .infinity }
        let s2 = side * side, sum2 = sum * sum
        return max(s2 * maxArea / sum2, sum2 / (s2 * minArea))
    }

    /// Satırı boş alanın kısa kenarı boyunca dizer; kalan boş alanı döndürür.
    private static func place(row: Range<Int>, items: [TreemapItem], areas: [Double], rowSum: Double, free: CGRect,
                              into out: inout [TreemapRect], isLast: Bool) -> CGRect {
        let horizontal = free.width >= free.height // geniş alanda satır sol kenarda dikey şerit olur
        if horizontal {
            let stripWidth = isLast ? free.width : CGFloat(rowSum / Double(free.height))
            var y = free.minY
            for index in row {
                let h = index == row.upperBound - 1 ? free.maxY - y : CGFloat(areas[index] / Double(stripWidth))
                out.append(TreemapRect(id: items[index].id, rect: CGRect(x: free.minX, y: y, width: stripWidth, height: h)))
                y += h
            }
            return CGRect(x: free.minX + stripWidth, y: free.minY, width: max(0, free.width - stripWidth), height: free.height)
        } else {
            let stripHeight = isLast ? free.height : CGFloat(rowSum / Double(free.width))
            var x = free.minX
            for index in row {
                let w = index == row.upperBound - 1 ? free.maxX - x : CGFloat(areas[index] / Double(stripHeight))
                out.append(TreemapRect(id: items[index].id, rect: CGRect(x: x, y: free.minY, width: w, height: stripHeight)))
                x += w
            }
            return CGRect(x: free.minX, y: free.minY + stripHeight, width: free.width, height: max(0, free.height - stripHeight))
        }
    }
}
