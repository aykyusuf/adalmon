import Foundation

/// Grafik altındaki özet: ortalama / en az / en çok. Saf mantık.
struct ChartStats: Equatable {
    var average: Double
    var minimum: Double
    var maximum: Double

    init?(values: [Double]) {
        guard let lo = values.min(), let hi = values.max() else { return nil }
        minimum = lo
        maximum = hi
        average = values.reduce(0, +) / Double(values.count)
    }

    /// "27,1 Ort · 21,5 Min · 33,4 Maks"
    func text(_ format: (Double) -> String) -> String {
        "\(format(average)) Ort · \(format(minimum)) Min · \(format(maximum)) Maks"
    }
}
