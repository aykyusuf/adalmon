import Foundation

/// Cihaz türü: simge ve başlık için.
enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case iPhone, iPad, watch, airPods, airPodsPro, airPodsMax, headphones, keyboard, mouse, trackpad, gamepad, other

    var symbol: String {
        switch self {
        case .iPhone: "iphone"
        case .iPad: "ipad"
        case .watch: "applewatch"
        case .airPods: "airpods"
        case .airPodsPro: "airpodspro"
        case .airPodsMax: "airpodsmax"
        case .headphones: "headphones"
        case .keyboard: "keyboard"
        case .mouse: "magicmouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .gamepad: "gamecontroller"
        case .other: "dot.radiowaves.left.and.right"
        }
    }

    var title: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .watch: "Apple Watch"
        case .airPods: "AirPods"
        case .airPodsPro: "AirPods Pro"
        case .airPodsMax: "AirPods Max"
        case .headphones: "Kulaklık"
        case .keyboard: "Klavye"
        case .mouse: "Fare"
        case .trackpad: "Trackpad"
        case .gamepad: "Oyun kolu"
        case .other: "Aksesuar"
        }
    }

    /// Sol / sağ / kutu ayrı gösterilen kulaklıklar.
    var hasPods: Bool { self == .airPods || self == .airPodsPro }

    /// Ad ve (varsa) Bluetooth küçük türünden tür tahmini.
    static func guess(name: String, minorType: String? = nil) -> DeviceKind {
        let n = name.lowercased()
        let m = (minorType ?? "").lowercased()
        if n.contains("airpods max") { return .airPodsMax }
        if n.contains("airpods pro") { return .airPodsPro }
        if n.contains("airpods") { return .airPods }
        if n.contains("iphone") { return .iPhone }
        if n.contains("ipad") { return .iPad }
        if n.contains("watch") { return .watch }
        if m.contains("keyboard") || n.contains("keyboard") || n.contains("klavye") { return .keyboard }
        if m.contains("mouse") || n.contains("mouse") || n.contains("fare") { return .mouse }
        if m.contains("trackpad") || n.contains("trackpad") { return .trackpad }
        if m.contains("gamepad") || m.contains("game") || n.contains("controller") { return .gamepad }
        if m.contains("headphone") || m.contains("headset") || n.contains("headphone") { return .headphones }
        return .other
    }
}
