import Foundation

/// Ağ widget'ının değeri: anlık hız ya da toplam miktar.
enum NetworkValueSource: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Anlık hız (B/s).
    case speed
    /// Son 60 saniyede aktarılan.
    case last60
    /// Bugün aktarılan (tüm arayüzler).
    case today
    /// Bugünkü mobil veri / günlük limit.
    case mobileToday

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speed: "Anlık hız"
        case .last60: "Son 60 sn"
        case .today: "Bugün"
        case .mobileToday: "Mobil (bugün)"
        }
    }

    /// Menü çubuğu etiketi.
    var shortLabel: String {
        switch self {
        case .speed: "AĞ"
        case .last60: "60 SN"
        case .today: "BUGÜN"
        case .mobileToday: "MOBİL"
        }
    }
}
