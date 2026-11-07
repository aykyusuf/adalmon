import SwiftUI

/// Canlı geçmişten ve kayıtlı (dakikalık / saatlik) toplamlardan grafik serileri kurar. Saf mantık.
enum PerformanceSeriesBuilder {
    /// Canlı: son `capacity` örnek; en yeni nokta `anchor`da, öncekiler `interval` sn aralıkla geriye.
    static func live(metric: PerformanceMetric, history h: PerformanceHistory, interval: Int, anchor: Date) -> [PerformanceChartSeries] {
        func points(_ values: [Double], scale: Double = 1) -> [PerformanceChartPoint] {
            let n = values.count
            return values.enumerated().map { i, v in
                PerformanceChartPoint(date: anchor.addingTimeInterval(-Double(n - 1 - i) * Double(interval)), value: v * scale)
            }
        }
        switch metric {
        case .cpu: return [.init(name: "Kullanım", color: metric.color, points: points(h.cpu, scale: 100), unit: .percent)]
        case .memory: return [.init(name: "Kullanılan", color: metric.color, points: points(h.memory, scale: 100), unit: .percent)]
        case .gpu: return [.init(name: "Kullanım", color: metric.color, points: points(h.gpu, scale: 100), unit: .percent)]
        case .disk:
            return [.init(name: "Okuma", color: .green, points: points(h.diskRead), unit: .bytesPerSecond),
                    .init(name: "Yazma", color: .mint, points: points(h.diskWrite), unit: .bytesPerSecond)]
        case .network:
            return [.init(name: "İndirme", color: .orange, points: points(h.down), unit: .bytesPerSecond),
                    .init(name: "Yükleme", color: .yellow, points: points(h.up), unit: .bytesPerSecond)]
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
