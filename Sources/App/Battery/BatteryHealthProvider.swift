import Foundation

/// Apple'ın Ayarlar'daki "Maksimum kapasite" değeri (system_profiler SPPowerDataType). ~80 ms; en çok 6 saatte bir,
/// arka plan kuyruğunda çalışır ve önbelleğe yazılır.
enum BatteryHealthProvider {
    static let refreshInterval: TimeInterval = 6 * 3_600
    private static let valueKey = "battery.appleMaxCapacity"
    private static let dateKey = "battery.appleMaxCapacityDate"

    struct Cached: Equatable, Sendable {
        var percent: Int?
        var date: Date?
    }

    static func cached(_ d: UserDefaults = .standard) -> Cached {
        Cached(percent: d.object(forKey: valueKey) as? Int, date: d.object(forKey: dateKey) as? Date)
    }

    static func needsRefresh(_ cached: Cached, now: Date = .now) -> Bool {
        guard let date = cached.date else { return true }
        return now.timeIntervalSince(date) >= refreshInterval
    }

    static func store(percent: Int?, now: Date = .now, _ d: UserDefaults = .standard) {
        if let percent { d.set(percent, forKey: valueKey) }
        d.set(now, forKey: dateKey)
    }

    /// `system_profiler SPPowerDataType -json` çıktısından "%86" → 86.
    static func parse(json: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for item in items {
            guard let info = item["sppower_battery_health_info"] as? [String: Any],
                  let text = info["sppower_battery_health_maximum_capacity"] as? String else { continue }
            let digits = text.filter(\.isNumber)
            if let v = Int(digits), (1...100).contains(v) { return v }
        }
        return nil
    }

    /// Arka planda çalıştırır (ana iş parçacığını bloklamaz).
    static func fetch() async -> Int? {
        await Task.detached(priority: .utility) { () -> Int? in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPPowerDataType", "-json"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return parse(json: data)
        }.value
    }
}
