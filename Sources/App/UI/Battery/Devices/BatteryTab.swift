import Foundation

/// Pil sayfasının üst bölmesi: Mac | Cihazlar | iPhone & iPad.
enum BatteryTab: String, CaseIterable, Identifiable, Sendable {
    case mac, devices, ios

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mac: "Mac"
        case .devices: "Cihazlar"
        case .ios: "iPhone & iPad"
        }
    }

    var symbol: String {
        switch self {
        case .mac: "laptopcomputer"
        case .devices: "airpods"
        case .ios: "iphone"
        }
    }
}
