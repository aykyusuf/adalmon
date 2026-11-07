import SwiftUI

/// Canlı geçmişten ve kayıtlı (dakikalık / saatlik) toplamlardan grafik serileri kurar. Saf mantık.
enum PerformanceSeriesBuilder {
    /// Canlı: sistem geçmişi tamponundaki gerçek zaman damgalı örnekler (aralık 1 sn ile kullanıcı aralığı arasında değişebilir).
    static func live(metric: PerformanceMetric, samples: [SystemSample]) -> [PerformanceChartSeries] {
        func points(_ value: (SystemSample) -> Double) -> [PerformanceChartPoint] {
            samples.map { PerformanceChartPoint(date: $0.time, value: value($0)) }
        }
        switch metric {
        case .cpu: return [.init(name: "Kullanım", color: metric.color, points: points { $0.cpu * 100 }, unit: .percent)]
        case .memory: return [.init(name: "Kullanılan", color: metric.color, points: points { $0.memory * 100 }, unit: .percent)]
        case .gpu: return [.init(name: "Kullanım", color: metric.color, points: points { $0.gpu * 100 }, unit: .percent)]
        case .disk:
            return [.init(name: "Okuma", color: .green, points: points(\.diskRead), unit: .bytesPerSecond),
                    .init(name: "Yazma", color: .mint, points: points(\.diskWrite), unit: .bytesPerSecond)]
        case .network:
            return [.init(name: "İndirme", color: .orange, points: points(\.down), unit: .bytesPerSecond),
                    .init(name: "Yükleme", color: .yellow, points: points(\.up), unit: .bytesPerSecond)]
        }
    }

    /// Grafik değeri metni: yüzde (bir ondalık) ya da bayt/sn.
    static func valueText(_ value: Double, unit: PerformanceChartSeries.Unit) -> String {
        switch unit {
        case .percent: "%" + max(0, value).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR")))
        case .bytesPerSecond: Format.rate(value)
        }
    }

    /// Kayıtlı: kova toplamları oranlara çevrilir (CPU/GPU %, bellek: RAM'in yüzdesi olarak uygulama ayak izi, disk B/sn).
    static func stored(metric: PerformanceMetric, totals: [ResourceTotalPoint], window: ResourceWindow, cores: Int, memoryTotal: Double) -> [PerformanceChartSeries] {
        let bucket = Double(window.bucketSeconds)
        func points(_ transform: (ResourceTotalPoint) -> Double) -> [PerformanceChartPoint] {
            totals.map { PerformanceChartPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: transform($0)) }
        }
        switch metric {
        case .cpu:
            return [.init(name: "Kullanım", color: metric.color,
                          points: points { min(100, $0.cpuNs / 1e9 / bucket / Double(max(1, cores)) * 100) }, unit: .percent)]
        case .gpu:
            return [.init(name: "Kullanım", color: metric.color, points: points { min(100, $0.gpuNs / 1e9 / bucket * 100) }, unit: .percent)]
        case .memory:
            return [.init(name: "Uygulama belleği", color: metric.color,
                          points: points { memoryTotal > 0 ? min(100, $0.footprint / memoryTotal * 100) : 0 }, unit: .percent)]
        case .disk:
            return [.init(name: "Okuma", color: .green, points: points { $0.readBytes / bucket }, unit: .bytesPerSecond),
                    .init(name: "Yazma", color: .mint, points: points { $0.writeBytes / bucket }, unit: .bytesPerSecond)]
        case .network:
            return []
        }
    }

    /// Ağ: arayüz saatlik toplamları (indirme+yükleme ayrımı yok; tek çizgi, bayt/sn).
    static func storedNetwork(_ hours: [UsageStore.HourPoint]) -> [PerformanceChartSeries] {
        [.init(name: "Toplam", color: .orange,
               points: hours.map { PerformanceChartPoint(date: Date(timeIntervalSince1970: TimeInterval($0.hour)), value: Double($0.total) / 3_600) },
               unit: .bytesPerSecond)]
    }

    /// Çizgi spark'ları için 0...1'e normalize edilmiş değerler.
    static func normalized(_ values: [Double], metric: PerformanceMetric) -> [Double] {
        switch metric {
        case .cpu, .memory, .gpu: return values
        case .disk, .network:
            let peak = max(1_000_000, values.max() ?? 0)
            return values.map { $0 / peak }
        }
    }
}
