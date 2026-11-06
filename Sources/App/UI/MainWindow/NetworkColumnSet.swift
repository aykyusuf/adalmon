import CoreGraphics

/// Ağ kullanımı tablosunda genişliğe göre görünen sütunlar. Ayrıntı paneli açıkken tablo daralır;
/// önce "Alan adları", sonra "Durum" sütunu gizlenir (Uygulama, Toplam ve Mobil her zaman kalır).
enum NetworkColumnSet: Equatable {
    case full, withoutDomains, essential

    static let fullMinWidth: CGFloat = 820
    static let withoutDomainsMinWidth: CGFloat = 440

    init(width: CGFloat) {
        if width >= Self.fullMinWidth {
            self = .full
        } else if width >= Self.withoutDomainsMinWidth {
            self = .withoutDomains
        } else {
            self = .essential
        }
    }

    var showsDomains: Bool { self == .full }
    var showsStatus: Bool { self != .essential }
}
