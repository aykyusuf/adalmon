@testable import Adalmon

/// Ofis v3 öncesi testlerin üç kademe adı: en yakın yeni kademelere eşlenir (eski testler yeni kademe sayılarıyla güncellendi).
extension OfficeRoomTier {
    static var small: OfficeRoomTier { .s2 }
    static var medium: OfficeRoomTier { .s6 }
    static var large: OfficeRoomTier { .s12 }
}
