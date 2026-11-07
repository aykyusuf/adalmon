import SwiftUI

struct MemoryPanelModel: Equatable {
    enum Pressure: Equatable {
        case normal, warning, critical
        var title: String { switch self { case .normal: "Normal"; case .warning: "Uyarı"; case .critical: "Kritik" } }
        var tint: Color { switch self { case .normal: .green; case .warning: .orange; case .critical: .red } }
        /// Gösterge dolgusu.
        var level: Double { switch self { case .normal: 0.2; case .warning: 0.6; case .critical: 1 } }
    }

    struct Part: Identifiable, Equatable {
        var id: String
        var title: String
        var value: String
        var fraction: Double
        var help: String
    }

    var hasData: Bool
    var bigValue: String
    var usedText: String
    var freeText: String
    var totalText: String
    var usedFraction: Double
    var pressure: Pressure
    var parts: [Part]
    var swapText: String
    var swapFraction: Double
    var series: PanelSeries
    var processes: [TopProcess]

    static func make(_ data: PanelData, processes: [TopProcess]) -> MemoryPanelModel {
        guard let m = data.snapshot?.memory else {
            return MemoryPanelModel(hasData: false, bigValue: "—", usedText: "—", freeText: "—", totalText: "—", usedFraction: 0,
                                    pressure: .normal, parts: [], swapText: "—", swapFraction: 0,
                                    series: .make(values: [], samples: [], format: .percent), processes: processes)
        }
        let total = max(1, Double(m.totalBytes))
        func part(_ id: String, _ title: String, _ bytes: UInt64, _ help: String) -> Part {
            Part(id: id, title: title, value: Format.bytes(bytes), fraction: min(1, Double(bytes) / total), help: help)
        }
        let free = m.totalBytes >= m.usedBytes ? m.totalBytes - m.usedBytes : 0
        let pressure: Pressure = switch m.pressure { case .normal: .normal; case .warning: .warning; case .critical: .critical }
        return MemoryPanelModel(
            hasData: true,
            bigValue: Format.bytes(m.usedBytes),
            usedText: Format.bytes(m.usedBytes),
            freeText: Format.bytes(free),
            totalText: Format.bytes(m.totalBytes),
            usedFraction: m.usedFraction,
            pressure: pressure,
            parts: [
                part("app", "Uygulama belleği", m.appBytes, "Uygulamaların kullandığı bellek"),
                part("wired", "Sabit (wired)", m.wiredBytes, "Çekirdek ve sürücülerin boşaltılamaz belleği"),
                part("compressed", "Sıkıştırılmış", m.compressedBytes, "Bellek yetmeyince sıkıştırılmış sayfalar"),
                part("cache", "Önbellek", m.cachedBytes, "Gerektiğinde hemen boşaltılabilen dosya önbelleği"),
            ],
            swapText: m.swapTotalBytes > 0 ? "\(Format.bytes(m.swapUsedBytes)) / \(Format.bytes(m.swapTotalBytes))" : Format.bytes(m.swapUsedBytes),
            swapFraction: m.swapTotalBytes > 0 ? min(1, Double(m.swapUsedBytes) / Double(m.swapTotalBytes)) : 0,
            series: .make(values: data.memHistory, samples: data.samples, format: .percent, scale: .fitted(minSpan: 0.1)),
            processes: processes)
    }
}
