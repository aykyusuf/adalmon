import Foundation

extension TierLevel {
    /// Kademeli limit basamağının Türkçe adı.
    var title: String {
        switch self {
        case .none: "Normal"
        case .warn: "Uyarı"
        case .slow: "Yavaşlatma"
        case .cut: "Kesme"
        }
    }
}
