import Foundation

/// Bir pil değerinin geldiği kaynak. Öncelik büyükten küçüğe birleştirmede kullanılır.
enum DeviceSource: String, Codable, Sendable {
    case lockdown        // libimobiledevice (iPhone/iPad, USB ya da Wi-Fi)
    case gatt            // CoreBluetooth Battery Service 0x180F / 0x2A19
    case hid             // IORegistry BatteryPercent (Magic Mouse/Keyboard/Trackpad)
    case advertisement   // AirPods BLE reklam paketi (10 puanlık adımlar)
    case systemCache     // system_profiler son bilinen değer

    var priority: Int {
        switch self {
        case .lockdown: 5
        case .gatt, .hid: 4
        case .advertisement: 2
        case .systemCache: 1
        }
    }

    /// Değer doğası gereği yaklaşık mı (adım adım ya da önbellek).
    var isApproximate: Bool { self == .advertisement || self == .systemCache }

    var title: String {
        switch self {
        case .lockdown: "Kablo / Wi-Fi (libimobiledevice)"
        case .gatt: "Bluetooth pil hizmeti"
        case .hid: "HID (IORegistry)"
        case .advertisement: "Bluetooth yayını"
        case .systemCache: "Sistem önbelleği"
        }
    }
}
