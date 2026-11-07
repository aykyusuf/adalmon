import Foundation

/// Pil sayfasının üst bölmesi: Mac | Cihazlar | iPhone & iPad | Şarj.
enum BatteryTab: String, CapsuleTabItem, Sendable {
    case mac, devices, ios, charging

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mac: "Mac"
        case .devices: "Cihazlar"
        case .ios: "iPhone & iPad"
        case .charging: "Şarj"
        }
    }

    var systemImage: String {
        switch self {
        case .mac: "laptopcomputer"
        case .devices: "headphones"
        case .ios: "iphone"
        case .charging: "bolt.batteryblock"
        }
    }
}
