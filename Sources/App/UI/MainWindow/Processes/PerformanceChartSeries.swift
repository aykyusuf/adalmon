import SwiftUI

typealias PerformanceChartPoint = ChartPoint

/// Performans grafiğinin bir çizgisi (CPU için tek, Disk/Ağ için iki: okuma-yazma / indirme-yükleme).
struct PerformanceChartSeries: Identifiable, Equatable {
    enum Unit: Equatable {
        /// 0-100 sabit eksen.
        case percent
        /// Bayt/sn, otomatik eksen.
        case bytesPerSecond
    }

    var name: String
    var color: Color
    var points: [PerformanceChartPoint]
    var unit: Unit
    var id: String { name }

    /// Etkileşimli grafik bileşenleri için seri.
    var line: ChartLine { ChartLine(name: name, color: color, points: points) }
}

extension PerformanceMetric {
    var color: Color {
        switch self {
        case .cpu: .blue
        case .memory: .purple
        case .disk: .green
        case .network: .orange
        case .gpu: .teal
        }
    }
}
