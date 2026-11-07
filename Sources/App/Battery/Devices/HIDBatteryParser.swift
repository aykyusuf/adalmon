import Foundation

/// IORegistry `AppleDeviceManagementHIDEventService` özelliklerinden (Magic Mouse/Keyboard/Trackpad) pil okuması.
enum HIDBatteryParser {
    static func reading(from props: [String: Any], now: Date = .now) -> DeviceReading? {
        guard let percent = (props["BatteryPercent"] as? NSNumber)?.intValue, (0...100).contains(percent) else { return nil }
        let name = (props["Product"] as? String) ?? (props["DeviceName"] as? String) ?? ""
        guard !name.isEmpty else { return nil }
        let kind = DeviceKind.guess(name: name, minorType: props["DeviceUsagePage"] as? String)
        // BatteryStatusFlags bit 0x01 = şarj oluyor (Magic Keyboard/Trackpad, kablo bağlı); doğrulanmadı, yoksa false.
        let flags = (props["BatteryStatusFlags"] as? NSNumber)?.intValue ?? 0
        return DeviceReading(name: name, kind: kind == .other ? .keyboard : kind, source: .hid, observedAt: now, level: percent,
                             isCharging: flags & 0x01 != 0, isConnected: true)
    }
}
