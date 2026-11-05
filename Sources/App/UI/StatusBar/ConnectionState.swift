import Foundation

/// Bağlantı noktası widget'ının durumu.
enum ConnectionState: Sendable, Equatable {
    /// Wi-Fi ya da Ethernet.
    case online
    /// Mobil veri (hotspot, hücresel, pahalı/kısıtlı yol).
    case mobile
    case offline
}
