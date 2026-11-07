import SwiftUI

/// Görev Yöneticisi'ndeki gibi ısı haritası: değer yükseldikçe hücre sarıdan turuncuya doyar.
/// Yoğunluk saf mantıktır (test edilir), renk açık/koyu temaya göre ayarlanır.
enum HeatTint {
    /// 0...1. Karekök ölçeği: küçük ama sıfır olmayan değerler de belli olur. `memoryTotal` bayt (bellek sütunu için).
    static func intensity(column: ProcessColumn, value: Double, memoryTotal: Double = 0) -> Double {
        let scaled: Double
        switch column {
        case .name, .category, .processCount, .pid: return 0
        case .cpu: scaled = value / 60
        case .memory: scaled = memoryTotal > 0 ? value / memoryTotal / 0.15 : 0
        case .disk: scaled = value / 50_000_000
        case .network: scaled = value / 5_000_000
        case .gpu: scaled = value / 50
        case .energy: scaled = value / 3
        }
        guard scaled > 0.0005 else { return 0 }
        return min(1, scaled.squareRoot())
    }

    /// Yoğunluğu 1/24 basamaklara yuvarlar: ufak dalgalanmalar 0,25 sn'lik renk geçişini boşuna tetiklemesin.
    static func quantized(_ t: Double) -> Double { (t * 24).rounded() / 24 }

    /// Sıfırda da aynı renk tonu (saydam): geçiş boş renkten turuncuya gri bir ara tondan geçmez.
    static func color(intensity t: Double, dark: Bool) -> Color {
        let low = (r: 1.0, g: 0.80, b: 0.22), high = (r: 1.0, g: 0.45, b: 0.10)
        let r = low.r + (high.r - low.r) * t, g = low.g + (high.g - low.g) * t, b = low.b + (high.b - low.b) * t
        guard t > 0 else { return Color(red: low.r, green: low.g, blue: low.b).opacity(0) }
        let alpha = dark ? 0.07 + 0.36 * t : 0.10 + 0.50 * t
        return Color(red: r, green: g, blue: b).opacity(alpha)
    }
}
