import Foundation

/// Pil sayfasının üst bölmesi: Mac | Cihazlar | iPhone & iPad | Şarj.
enum BatteryTab: String, CaseIterable, Identifiable, Sendable {
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

    var symbol: String {
        switch self {
        case .mac: "laptopcomputer"
        case .devices: "airpods"
        case .ios: "iphone"
        case .charging: "bolt.badge.clock"
        }
    }
}
