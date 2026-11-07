import Foundation

/// Metrik panelindeki 60 sn'lik grafik verisi. Saf veri: imleç okuması metni buradan üretilir (testlenir).
struct PanelSeries: Equatable {
    enum ValueFormat: Equatable { case percent, rate, temperature }

    var values: [Double]
    var times: [Date]
    var format: ValueFormat
    /// Pencere uzunluğu (sn); x ekseni sağda "şimdi" olacak şekilde zamana göre ölçeklenir.
    var window: TimeInterval = 60
    /// nil: biçime göre varsayılan ölçek.
    var scale: PanelSparklineScale?

    var isEmpty: Bool { values.count < 2 }

    var resolvedScale: PanelSparklineScale {
        if let scale { return scale }
        switch format {
        case .percent: return .fixed(0...1)
        case .rate: return .zeroBased(floor: 50_000)
        case .temperature: return .fitted(minSpan: 12)
        }
    }

    func text(_ value: Double) -> String {
        switch format {
        case .percent: Format.percent(value)
        case .rate: Format.rate(value)
        case .temperature: "\(Int(value.rounded())) °C"
        }
    }

    /// `x` (0...1, soldan sağa) konumuna en yakın örnek: "12 sn önce · %34".
    func readout(atFraction x: Double, now: Date? = nil) -> (index: Int, text: String)? {
        guard !values.isEmpty, values.count == times.count, let last = times.last else { return nil }
        let reference = now ?? last
        let target = reference.addingTimeInterval(-window * (1 - min(1, max(0, x))))
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (i, t) in times.enumerated() {
            let d = abs(t.timeIntervalSince(target))
            if d < bestDistance { bestDistance = d; best = i }
        }
        let ago = Int(max(0, reference.timeIntervalSince(times[best])).rounded())
        let when = ago == 0 ? "şimdi" : "\(ago) sn önce"
        return (best, "\(when) · \(text(values[best]))")
    }

    /// Ham değer dizisinden zaman damgası türetir (örneklerin son N zamanını kullanır, yetmezse 1 sn adım).
    static func make(values: [Double], samples: [SystemSample], format: ValueFormat, scale: PanelSparklineScale? = nil) -> PanelSeries {
        let sampleTimes = samples.map(\.time)
        let times: [Date]
        if values.count <= sampleTimes.count {
            times = Array(sampleTimes.suffix(values.count))
        } else {
            let end = sampleTimes.last ?? .now
            times = values.indices.map { end.addingTimeInterval(-Double(values.count - 1 - $0)) }
        }
        return PanelSeries(values: values, times: times, format: format, scale: scale)
    }
}
