import SwiftUI

struct TemperaturePanelModel: Equatable {
    struct Group: Identifiable, Equatable {
        var source: TemperatureSource
        var title: String
        var value: String
        var celsius: Double
        var id: TemperatureSource { source }
    }

    struct Sensor: Identifiable, Equatable {
        var name: String
        var value: String
        var celsius: Double
        var id: String { name }
    }

    var hasData: Bool
    var headline: String
    var groups: [Group]
    var sensors: [Sensor]
    var series: PanelSeries
    var seriesTitle: String

    static func make(_ data: PanelData) -> TemperaturePanelModel {
        guard let t = data.snapshot?.temperature else {
            return TemperaturePanelModel(hasData: false, headline: "—", groups: [], sensors: [],
                                         series: PanelSeries(values: [], times: [], format: .temperature), seriesTitle: "CPU")
        }
        func deg(_ v: Double) -> String { "\(Int(v.rounded())) °C" }
        var groups: [Group] = []
        if let v = t.cpu { groups.append(Group(source: .cpu, title: "CPU ortalama", value: deg(v), celsius: v)) }
        if let v = t.cpuMax { groups.append(Group(source: .cpuMax, title: "CPU en sıcak", value: deg(v), celsius: v)) }
        if let v = t.gpu { groups.append(Group(source: .gpu, title: "GPU", value: deg(v), celsius: v)) }
        if let v = t.ssd { groups.append(Group(source: .ssd, title: "SSD", value: deg(v), celsius: v)) }
        if let v = t.battery { groups.append(Group(source: .battery, title: "Pil", value: deg(v), celsius: v)) }
        let sensors = t.sensors.map { Sensor(name: $0.key, value: deg($0.value), celsius: $0.value) }
            .sorted { $0.celsius != $1.celsius ? $0.celsius > $1.celsius : $0.name < $1.name }
        let cpuSeries = data.temperatureSeries[.cpu] ?? data.temperatureHistory
        return TemperaturePanelModel(
            hasData: true,
            headline: (t.cpu ?? t.cpuMax ?? t.gpu).map(deg) ?? "—",
            groups: groups, sensors: sensors,
            series: .make(values: cpuSeries, samples: data.samples, format: .temperature),
            seriesTitle: "CPU ortalama")
    }
}
