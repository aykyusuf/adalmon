import Foundation

/// Bir kuralın (ya da kademeli limitin) hangi ağda etkili olduğu.
enum NetworkScope: String, Codable, Sendable, CaseIterable {
    /// Yalnızca mobil veri (iPhone hotspot / USB tethering). Sayaç da yalnızca mobil byte'ları sayar.
    case mobileOnly
    /// Tüm ağlar (Wi-Fi dahil). Sayaç tüm trafiği sayar.
    case allNetworks
}


/// Elle engelin hangi ağda geçerli olduğu. Saklama: `blockedOnMobile` (mobil) + `blockedOnWiFi` (ölçülmeyen ağ:
/// Wi-Fi/kablolu); ikisinde birden olan uygulama "her yerde" engellidir. Böylece mobil listesini okuyan her yer
/// (panel, Ayarlar, Süreçler, Kestirmeler) "her yerde" engelini de görür ve kaldırabilir.
enum BlockScope: String, Codable, Sendable, CaseIterable, Identifiable {
    case mobile
    case wifi
    case everywhere

    var id: String { rawValue }

    /// Menüdeki seçenek adı.
    var title: String {
        switch self {
        case .mobile: "Mobilde"
        case .wifi: "Wi-Fi'de"
        case .everywhere: "Her yerde"
        }
    }

    /// Cümle içi ("Chrome mobil veride engellendi").
    var phrase: String {
        switch self {
        case .mobile: "mobil veride"
        case .wifi: "Wi-Fi/kablolu ağda"
        case .everywhere: "her ağda"
        }
    }

    /// Seçilen kapsam şu anki ağı etkilemiyorsa kısa not (boş = şu an etkili).
    func note(onMobile: Bool) -> String {
        switch self {
        case .mobile where !onMobile: " (şu an Wi-Fi/kablolu ağdasın, etkilenmez)"
        case .wifi where onMobile: " (şu an mobil veridesin, etkilenmez)"
        default: ""
        }
    }

    /// Satır rozeti.
    var badge: String { "\(title) engelli" }

    var blocksMobile: Bool { self != .wifi }
    var blocksWiFi: Bool { self != .mobile }

    /// İki listedeki üyelikten kapsam (ikisi de yoksa engel yok).
    static func from(mobile: Bool, wifi: Bool) -> BlockScope? {
        switch (mobile, wifi) {
        case (true, true): .everywhere
        case (true, false): .mobile
        case (false, true): .wifi
        case (false, false): nil
        }
    }
}
