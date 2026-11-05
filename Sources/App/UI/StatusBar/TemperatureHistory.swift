import Foundation

/// Sıcaklık geçmişi (AppModel'de yok). Aynı örnek birden çok kez okunursa (menü çubuğu + ayarlar önizlemesi)
/// zaman damgasıyla tekilleştirilir; her örnek yalnızca bir kez eklenir.
@MainActor
final class TemperatureHistory {
    static let shared = TemperatureHistory()

    private(set) var series: [TemperatureSource: [Double]] = [:]
    private var lastTimestamp: Date?

    func record(_ snapshot: SystemSnapshot?) -> [TemperatureSource: [Double]] {
        guard let snapshot, let t = snapshot.temperature, snapshot.timestamp != lastTimestamp else { return series }
        lastTimestamp = snapshot.timestamp
        let readings: [TemperatureSource: Double?] = [.cpu: t.cpu, .cpuMax: t.cpuMax, .gpu: t.gpu, .ssd: t.ssd, .battery: t.battery]
        for (source, value) in readings {
            guard let value else { continue }
            var s = series[source, default: []]
            s.append(value)
            if s.count > AppModel.historyLength { s.removeFirst(s.count - AppModel.historyLength) }
            series[source] = s
        }
        return series
    }
}
