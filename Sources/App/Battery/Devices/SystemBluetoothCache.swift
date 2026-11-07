import Foundation

/// `system_profiler SPBluetoothDataType -json` çıktısından son bilinen pil değerleri ve eşleşmiş cihaz listesi.
/// Çıktı AirPods için `device_batteryLevelLeft/Right/Case` (örn. "75%"), tek pilli cihazlar için `device_batteryLevelMain` taşır.
struct SystemBluetoothCache: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var name: String
        var kind: DeviceKind
        var productID: Int?
        var connected: Bool
        var level: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?
    }

    var entries: [Entry] = []

    static func parse(json data: Data) -> SystemBluetoothCache {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return SystemBluetoothCache() }
        var entries: [Entry] = []
        for section in sections {
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                for item in section[key] as? [[String: Any]] ?? [] {
                    for (name, value) in item {
                        guard let props = value as? [String: Any] else { continue }
                        entries.append(Entry(
                            name: name.trimmingCharacters(in: .whitespaces),
                            kind: DeviceKind.guess(name: name, minorType: props["device_minorType"] as? String),
                            productID: (props["device_productID"] as? String).flatMap(hex),
                            connected: connected,
                            level: pct(props["device_batteryLevelMain"]),
                            left: pct(props["device_batteryLevelLeft"]),
                            right: pct(props["device_batteryLevelRight"]),
                            caseLevel: pct(props["device_batteryLevelCase"])))
                    }
                }
            }
        }
        return SystemBluetoothCache(entries: entries)
    }

    /// Pil bilgisi olan girdiler `DeviceReading` olur (yaklaşık, önbellek).
    func readings(now: Date = .now) -> [DeviceReading] {
        entries.compactMap { e in
            let r = DeviceReading(name: e.name, kind: e.kind, source: .systemCache, observedAt: now, level: e.level, left: e.left,
                                  right: e.right, caseLevel: e.caseLevel, isConnected: e.connected)
            return r.hasAnyLevel ? r : nil
        }
    }

    /// Reklam paketindeki ürün kimliğiyle eşleşmiş cihaz (kulaklık).
    func entry(productID: Int) -> Entry? { entries.first { $0.productID == productID } }

    static func hex(_ s: String) -> Int? {
        let t = s.lowercased().hasPrefix("0x") ? String(s.dropFirst(2)) : s
        return Int(t, radix: 16)
    }

    private static func pct(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return (0...100).contains(n.intValue) ? n.intValue : nil }
        guard let s = v as? String else { return nil }
        let digits = s.filter(\.isNumber)
        guard let n = Int(digits), (0...100).contains(n) else { return nil }
        return n
    }

    /// Gerçek çalıştırma (arka plan iş parçacığında çağrılmalı). ~60 ms.
    static func capture(timeout: TimeInterval = 8) -> SystemBluetoothCache {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return SystemBluetoothCache() }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return parse(json: data)
    }
}
