import Foundation

/// AirPods / Beats "proximity pairing" BLE reklam paketi çözümleyicisi.
///
/// Biçim (Apple Continuity; tersine mühendislik — resmi belge yok). Kaynaklar:
///  - furiousMAC/continuity, "Proximity Pairing Message" (https://github.com/furiousMAC/continuity/blob/master/messages/proximity_pairing.md)
///  - OpenPods (adolfintel/OpenPods, `PodsService.java`): nibble sırası, `flip` ve şarj bitleri
///  - delphiki/AirStatus (Python): aynı alanlar, 27 baytlık veri
///
/// CoreBluetooth `CBAdvertisementDataManufacturerDataKey` baytları: `4C 00` (Apple, little endian) + TLV listesi.
/// TLV: `[tip][uzunluk][yük…]`. Tip 0x07 = proximity pairing, uzunluk 0x19 (25). Yük:
///   0 ön ek (0x01 = eşleşmiş)   1-2 model (little endian = Bluetooth ürün kimliği, ör. 0E 20 → 0x200E AirPods Pro)
///   3 durum (bit 0x20: kulak yönü / "flip")   4 pil: iki nibble (kulaklar)   5 yüksek nibble şarj bayrakları, düşük nibble kutu pili
///   6 kapak sayacı (bit 0x08 = 0 → kapak açık)   7 renk   8 son ek   9…24 şifreli yük
/// Pil nibble: 0…10 → ×10 %, 0xF = bilinmiyor. Şarj bitleri: 1 = sol, 2 = sağ, 4 = kutu (flip ise sol/sağ yer değiştirir).
/// Not: Bu çözümleme gerçek cihazla bu makinede DOĞRULANMADI; bayt düzeni yukarıdaki kaynaklardan.
struct AppleProximityAdvertisement: Equatable, Sendable {
    var productID: Int
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var leftCharging: Bool
    var rightCharging: Bool
    var caseCharging: Bool
    var lidOpen: Bool

    var kind: DeviceKind { Self.kind(forProductID: productID) }

    /// Bluetooth ürün kimliği → tür. Kaynak: furiousMAC tablosu + Apple ürün kimlikleri.
    static func kind(forProductID id: Int) -> DeviceKind {
        switch id {
        case 0x200E, 0x2014, 0x2024: .airPodsPro
        case 0x200A: .airPodsMax
        case 0x2002, 0x200F, 0x2013, 0x2019, 0x201B: .airPods
        default: .headphones
        }
    }

    static let appleCompanyID: UInt16 = 0x004C
    static let proximityType: UInt8 = 0x07

    /// `manufacturerData`: CoreBluetooth'ın verdiği (şirket kimliği öneki dahil) baytlar.
    static func parse(manufacturerData data: Data) -> AppleProximityAdvertisement? {
        let b = [UInt8](data)
        guard b.count >= 4, b[0] == 0x4C, b[1] == 0x00 else { return nil }
        var i = 2
        while i + 2 <= b.count {
            let type = b[i], length = Int(b[i + 1])
            let start = i + 2
            guard start + length <= b.count else { return nil }
            if type == proximityType { return parse(payload: Array(b[start..<start + length])) }
            i = start + length
        }
        return nil
    }

    static func parse(payload p: [UInt8]) -> AppleProximityAdvertisement? {
        guard p.count >= 7, p[0] == 0x01 else { return nil }
        let productID = Int(p[1]) | Int(p[2]) << 8
        let flip = (p[3] & 0x20) == 0
        let hi = p[4] >> 4, lo = p[4] & 0x0F
        let charge = p[5] >> 4
        let leftBit: UInt8 = flip ? 0b10 : 0b01
        let rightBit: UInt8 = flip ? 0b01 : 0b10
        return AppleProximityAdvertisement(
            productID: productID,
            left: percent(flip ? hi : lo), right: percent(flip ? lo : hi), caseLevel: percent(p[5] & 0x0F),
            leftCharging: charge & leftBit != 0, rightCharging: charge & rightBit != 0, caseCharging: charge & 0b100 != 0,
            lidOpen: p[6] & 0x08 == 0)
    }

    private static func percent(_ nibble: UInt8) -> Int? { nibble <= 10 ? Int(nibble) * 10 : nil }
}
