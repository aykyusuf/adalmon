import Foundation

/// Bir kuralın (ya da kademeli limitin) hangi ağda etkili olduğu.
enum NetworkScope: String, Codable, Sendable, CaseIterable {
    /// Yalnızca mobil veri (iPhone hotspot / USB tethering). Sayaç da yalnızca mobil byte'ları sayar.
    case mobileOnly
    /// Tüm ağlar (Wi-Fi dahil). Sayaç tüm trafiği sayar.
    case allNetworks
}
