import Foundation

/// Zaman damgasız (sıra numaralı) geçmişleri etkileşimli grafikte çizmek için yapay x ekseni: i. örnek = referans + i sn.
/// Eksen gizlidir; yalnızca ipucundaki "yaklaşık N sn önce" metni için kullanılır. Saf mantık.
@MainActor
enum SampleAxis {
    static func date(_ index: Double) -> Date { Date(timeIntervalSinceReferenceDate: index) }

    /// Son `capacity` örnek penceresinde en yeni örnek sağ uçta olacak şekilde noktalar.
    static func points(_ values: [Double], capacity: Int) -> [ChartPoint] {
        let offset = max(0, capacity - values.count)
        return values.enumerated().map { ChartPoint(date: date(Double(offset + $0.offset)), value: $0.element) }
    }

    /// İpucu başlığı: x konumuna (yapay tarih) göre "şimdi" / "~N sn önce" / "~N dk önce".
    static func ageText(of date: Date, count: Int, secondsPerPoint: Int, capacity: Int = AppModel.historyLength) -> String {
        let index = Int(date.timeIntervalSinceReferenceDate.rounded())
        let newest = max(capacity, count) - 1
        let ago = max(0, newest - index) * max(1, secondsPerPoint)
        if ago == 0 { return "şimdi" }
        return ago < 120 ? "~\(ago) sn önce" : "~\(ago / 60) dk önce"
    }
}
