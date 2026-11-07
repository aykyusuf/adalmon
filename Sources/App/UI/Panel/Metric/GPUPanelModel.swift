import SwiftUI

struct GPUPanelModel: Equatable {
    var hasData: Bool
    var bigValue: String
    /// Gerçek yük (frekans ağırlıklı); yoksa nil.
    var loadText: String?
    var busyText: String
    var frequencyText: String?
    var frequencyFraction: Double?
    var temperature: String?
    var memory: String?
    var rendererText: String?
    var tilerText: String?
    var series: PanelSeries
    var processes: [TopProcess]

    static func make(_ data: PanelData, processes: [TopProcess]) -> GPUPanelModel {
        let g = data.snapshot?.gpu
        let freq = g?.frequencyMHz
        return GPUPanelModel(
            hasData: g != nil,
            bigValue: Format.percent(g?.displayLoad ?? 0),
            loadText: g?.load.map(Format.percent),
            busyText: Format.percent(g?.utilization ?? 0),
            frequencyText: freq.map(Format.gigahertz),
            frequencyFraction: freq.flatMap { f in g?.maxFrequencyMHz.map { $0 > 0 ? min(1, f / $0) : 0 } },
            temperature: data.snapshot?.temperature?.gpu.map { "\(Int($0.rounded())) °C" },
            memory: g?.memoryUsedBytes.map(Format.bytes),
            rendererText: g?.rendererUtilization.map(Format.percent),
            tilerText: g?.tilerUtilization.map(Format.percent),
            series: .make(values: data.gpuHistory, samples: data.samples, format: .percent),
            processes: processes)
    }
}
