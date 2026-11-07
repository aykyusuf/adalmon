import Foundation
@testable import Adalmon

extension PanelData {
    /// Metrik panelleri için zengin sahte veri: 10 çekirdek (4E + 6P), 60 örnek, sıcaklık sensörleri.
    static var metricSample: PanelData {
        var data = PanelData.sample
        let now = Date()
        let samples: [SystemSample] = (0..<60).map { i in
            let w = 0.5 + 0.5 * sin(Double(i) / 7)
            return SystemSample(time: now.addingTimeInterval(Double(i - 59)), cpu: 0.18 + 0.28 * w, memory: 0.6 + 0.02 * w,
                                gpu: 0.06 + 0.2 * w, diskRead: 2_000_000 * w, diskWrite: 900_000 * (1 - w) + 120_000,
                                down: 3_200_000 * w + 100_000, up: 240_000 * (1 - w) + 20_000)
        }
        data.samples = samples
        data.cpuHistory = samples.map(\.cpu)
        data.gpuHistory = samples.map(\.gpu)
        data.memHistory = samples.map(\.memory)
        let temps = samples.indices.map { 46 + 14 * sin(Double($0) / 9) }
        data.temperatureHistory = temps
        data.temperatureSeries = [.cpu: temps, .gpu: temps.map { $0 - 6 }]
        if var s = data.snapshot {
            s.cpu = CPUStats(total: 0.33, user: 0.22, system: 0.11,
                             perCore: [0.12, 0.2, 0.08, 0.31, 0.74, 0.52, 0.66, 0.9, 0.18, 0.4],
                             performanceCores: 6, efficiencyCores: 4, loadAverage: [3.42, 2.87, 2.31])
            s.temperature = TemperatureStats(cpu: 44, cpuMax: 53, gpu: 41, ssd: 36, battery: 31,
                                             sensors: ["PMU tdie1": 44, "PMU tdie2": 46, "PMU tdie3": 51, "PMU tdie4": 53, "PMU tdie5": 45, "PMU tdie6": 43,
                                                       "NAND CH0 temp": 36, "gas gauge battery": 31, "GPU MTR Temp Sensor1": 41])
            s.gpu = GPUStats(utilization: 0.28, rendererUtilization: 0.26, tilerUtilization: 0.07, memoryUsedBytes: 1_300_000_000,
                             load: 0.11, activeResidency: 0.3, frequencyMHz: 920, maxFrequencyMHz: 1_578)
            s.memory.pressure = .normal
            data.snapshot = s
        }
        return data
    }

    static let metricProcesses: [TopProcess] = [
        TopProcess(key: "/Applications/Safari.app", name: "Safari", valueText: "%14,2", fraction: 1),
        TopProcess(key: "/System/Applications/Music.app", name: "Müzik", valueText: "%6,8", fraction: 0.48),
        TopProcess(key: "/System/Applications/Mail.app", name: "Mail", valueText: "%3,1", fraction: 0.22),
        TopProcess(key: "/System/Applications/Messages.app", name: "Mesajlar", valueText: "%1,4", fraction: 0.1),
        TopProcess(key: "/System/Applications/Notes.app", name: "Notlar", valueText: "%0,6", fraction: 0.04),
    ]
}
