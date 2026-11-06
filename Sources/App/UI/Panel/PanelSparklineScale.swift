import Foundation

/// Mini grafiğin dikey ölçeği.
enum PanelSparklineScale: Equatable {
    /// Sabit aralık (ör. yüzde için 0...1).
    case fixed(ClosedRange<Double>)
    /// 0'dan en yüksek değere (en az `floor`) kadar; hız grafikleri için.
    case zeroBased(floor: Double)
    /// Değerlere sığdırılır; aralık en az `minSpan` kadardır (sıcaklık için).
    case fitted(minSpan: Double)

    func range(for values: [Double]) -> ClosedRange<Double> {
        switch self {
        case .fixed(let range):
            return range
        case .zeroBased(let floor):
            return 0...max(values.max() ?? 0, floor)
        case .fitted(let minSpan):
            guard let lo = values.min(), let hi = values.max() else { return 0...minSpan }
            let span = max(hi - lo, minSpan)
            let mid = (hi + lo) / 2
            return (mid - span / 2)...(mid + span / 2)
        }
    }
}
