import Foundation

/// Cihaz başına düşük pil eşik geçişleri (histerezisli; ilk görülmede susturulur; şarjdayken uyarmaz).
struct DeviceAlertEngine: Sendable {
    static let hysteresis = 3

    private var fired: [String: Set<Int>] = [:]
    private var known: Set<String> = []

    init() {}

    mutating func evaluate(_ devices: [DeviceBattery], settings: [String: DeviceSettings]) -> [BatteryAlertEvent] {
        var events: [BatteryAlertEvent] = []
        for d in devices {
            let s = settings[d.id] ?? DeviceSettings()
            guard let level = d.summaryLevel else { continue }
            var set = fired[d.id] ?? []
            // Yeniden silahlanma.
            set = set.filter { level <= $0 + Self.hysteresis && !d.isCharging }
            let live = d.isConnected && !d.isStale && !d.isCharging
            let first = !known.contains(d.id)
            known.insert(d.id)
            let crossed = s.lowThresholds.filter { level <= $0 && !set.contains($0) }
            if live || first { set.formUnion(crossed) }
            fired[d.id] = set
            guard live, !first, s.alertEnabled, !s.hidden, s.action.enabled,
                  let worst = crossed.min() else { continue }
            events.append(BatteryAlertEvent(kind: .low(worst), level: level, minutes: nil, action: s.action, subject: d.name))
        }
        return events
    }
}
