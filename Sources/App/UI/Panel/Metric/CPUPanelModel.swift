import SwiftUI

/// CPU paneli içeriği (saf; `PanelData` + canlı süreç listesi).
struct CPUPanelModel: Equatable {
    struct Core: Identifiable, Equatable {
        var index: Int
        var label: String
        var isEfficiency: Bool
        var fraction: Double
        var id: Int { index }
    }

    var hasData: Bool
    var total: Double
    var bigValue: String
    var userText: String
    var systemText: String
    var userFraction: Double
    var systemFraction: Double
    var topologyText: String
    var cores: [Core]
    var loadAverages: [String]
    var temperatureAverage: String?
    var temperatureMax: String?
    var series: PanelSeries
    var processes: [TopProcess]

    static func make(_ data: PanelData, processes: [TopProcess]) -> CPUPanelModel {
        let c = data.snapshot?.cpu
        let t = data.snapshot?.temperature
        var cores: [Core] = []
        if let c {
            // Apple Silicon: önce verimlilik (E), sonra performans (P) çekirdekleri.
            let e = c.efficiencyCores
            var eIndex = 0, pIndex = 0
            for (i, v) in c.perCore.enumerated() {
                let isE = i < e
                if isE { eIndex += 1 } else { pIndex += 1 }
                cores.append(Core(index: i, label: isE ? "E\(eIndex)" : "P\(pIndex)", isEfficiency: isE, fraction: min(1, max(0, v))))
            }
        }
        let load = (c?.loadAverage ?? []).map { $0.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "tr_TR"))) }
        return CPUPanelModel(
            hasData: c != nil,
            total: c?.total ?? 0,
            bigValue: Format.percent(c?.total ?? 0),
            userText: Format.percent(c?.user ?? 0),
            systemText: Format.percent(c?.system ?? 0),
            userFraction: c?.user ?? 0,
            systemFraction: c?.system ?? 0,
            topologyText: c.map { $0.performanceCores + $0.efficiencyCores > 0 ? "\($0.performanceCores) P + \($0.efficiencyCores) E çekirdek" : "\($0.perCore.count) çekirdek" } ?? "",
            cores: cores,
            loadAverages: load,
            temperatureAverage: t?.cpu.map { "\(Int($0.rounded())) °C" },
            temperatureMax: t?.cpuMax.map { "\(Int($0.rounded())) °C" },
            series: .make(values: data.cpuHistory, samples: data.samples, format: .percent),
            processes: processes)
    }
}
