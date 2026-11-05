import Foundation

/// Sıcaklıkları IOHID sensörlerinden okur; en fazla 15 sn'de bir gerçek okuma yapar (pil), arada son değeri döner.
///
/// Sensör adı kalıpları (M-serisi) exelban/Stats `Modules/Sensors/values.swift` (HID sensör listesi) ve
/// vladkens/macmon `src/metrics.rs` / `src/sources.rs` temel alınarak seçildi:
/// - CPU: "PMU tdie*" (M3/M4 çekirdek die), "pACC MTR Temp Sensor*", "eACC MTR Temp Sensor*" (M1/M2)
/// - GPU: "GPU MTR Temp Sensor*"
/// - SSD: "NAND CH* temp" / "SSD*"
/// - Pil: "gas gauge battery" / "Battery*"
/// Makul olmayan değerler (<5 veya >130 °C) atılır.
/// Thread safety: yalnızca tek seri kuyruktan çağrılmalı (`MetricsSampler` ile aynı varsayım).
final class TemperatureSampler {
    private static let minimumInterval: TimeInterval = 15
    private static let plausibleRange = 5.0...130.0

    private let sensors = HIDTemperatureSensors(isRelevant: TemperatureSampler.isRelevantSensor)
    /// M4 gibi IOHID'de "GPU MTR Temp Sensor" olmayan çiplerde GPU sıcaklığı için. Yalnızca IOHID GPU
    /// vermediğinde ilk kez açılır (ilk seferde ~2800 anahtar bir kez sayılır, ~30-40 ms).
    private lazy var smc: SMCReader? = SMCReader()
    private var lastRead: Date?
    private var cached: TemperatureStats?

    func sample() -> TemperatureStats? {
        let now = Date()
        if let lastRead, now.timeIntervalSince(lastRead) < Self.minimumInterval {
            return cached
        }
        lastRead = now
        let hid = Self.classify(sensors.readAll())
        cached = hid?.gpu == nil ? Self.merge(hid, smcGPU: smc?.gpuTemperatures() ?? [:]) : hid
        return cached
    }

    /// Okunmaya değer sensörler (CPU/GPU/SSD/pil kalıpları); diğerleri IPC maliyeti yüzünden atlanır.
    @Sendable static func isRelevantSensor(_ name: String) -> Bool {
        // Her sensör okuması ~0,8 ms; M3/M4'teki 14 "PMU tdie" yerine 6 örnek (1,3,5,7,9,11) yeterli.
        if name.hasPrefix("PMU tdie") {
            guard let n = Int(name.dropFirst("PMU tdie".count)) else { return false }
            return n % 2 == 1 && n <= 11
        }
        return name.hasPrefix("pACC MTR Temp Sensor") || name.hasPrefix("eACC MTR Temp Sensor")
            || name.hasPrefix("GPU MTR Temp Sensor") || name.hasPrefix("NAND CH") || name.hasPrefix("SSD")
            || name == "gas gauge battery" || name.hasPrefix("Battery")
    }

    /// Ham sensör değerlerini sınıflandırır; hiç geçerli sensör yoksa nil.
    static func classify(_ raw: [String: Double]) -> TemperatureStats? {
        let valid = raw.filter { plausibleRange.contains($0.value) }
        guard !valid.isEmpty else { return nil }

        func values(where match: (String) -> Bool) -> [Double] {
            valid.filter { match($0.key) }.map(\.value)
        }
        func average(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        // PMU tdie varsa (M3/M4) çekirdek die sensörleri bunlardır; yoksa ACC sensörlerine düş.
        var cpuValues = values { $0.hasPrefix("PMU tdie") }
        if cpuValues.isEmpty {
            cpuValues = values { $0.hasPrefix("pACC MTR Temp Sensor") || $0.hasPrefix("eACC MTR Temp Sensor") }
        }
        let gpuValues = values { $0.hasPrefix("GPU MTR Temp Sensor") }
        let ssdValues = values { $0.hasPrefix("NAND CH") || $0.hasPrefix("SSD") }
        let batteryValues = values { $0 == "gas gauge battery" || $0.hasPrefix("Battery") }

        return TemperatureStats(
            cpu: average(cpuValues),
            cpuMax: cpuValues.max(),
            gpu: average(gpuValues),
            ssd: average(ssdValues),
            battery: average(batteryValues),
            sensors: valid
        )
    }

    /// IOHID sonucuna SMC GPU sıcaklıklarını ekler. IOHID GPU verdiyse ya da SMC boşsa dokunmaz;
    /// CPU her zaman IOHID'den kalır. Ham değerler `sensors` içine "SMC <anahtar>" adıyla eklenir.
    static func merge(_ hid: TemperatureStats?, smcGPU: [String: Double]) -> TemperatureStats? {
        let valid = smcGPU.filter { plausibleRange.contains($0.value) }
        guard hid?.gpu == nil, !valid.isEmpty else { return hid }
        var stats = hid ?? TemperatureStats()
        stats.gpu = valid.values.reduce(0, +) / Double(valid.count)
        for (key, value) in valid {
            stats.sensors["SMC \(key)"] = value
        }
        return stats
    }
}
