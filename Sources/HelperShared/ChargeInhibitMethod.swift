import Foundation

/// Apple Silicon'da şarjı durduran SMC yöntemi. Hangisinin var olduğu çalışma zamanında anahtar sorgusuyla bulunur;
/// hiçbiri yoksa şarj sınırı DESTEKLENMEZ (tahmin edilmez).
enum ChargeInhibitMethod: String, Codable, Sendable, Equatable {
    /// macOS 15+ "CHTE" (4 bayt): 01 00 00 00 = şarj durur.
    case chte
    /// Eski "CH0B" + "CH0C" (1 bayt): 02 = şarj durur.
    case ch0bc

    var keys: [SMCKey] {
        switch self {
        case .chte: [.chte]
        case .ch0bc: [.ch0b, .ch0c]
        }
    }

    var title: String {
        switch self {
        case .chte: "CHTE"
        case .ch0bc: "CH0B/CH0C"
        }
    }

    /// Anahtar boyutlarından yöntemi seçer; beklenen boyutta değilse nil (yazma denenmez).
    static func detect(sizes: [SMCKey: Int]) -> ChargeInhibitMethod? {
        if sizes[.chte] == 4 { return .chte }
        if sizes[.ch0b] == 1, sizes[.ch0c] == 1 { return .ch0bc }
        return nil
    }

    /// SMC'den okunan baytlardan "şarj engelli mi".
    func isInhibiting(_ values: [SMCKey: [UInt8]]) -> Bool? {
        switch self {
        case .chte:
            guard let b = values[.chte], b.count == 4 else { return nil }
            return b.contains { $0 != 0 }
        case .ch0bc:
            guard let b = values[.ch0b], let c = values[.ch0c], b.count == 1, c.count == 1 else { return nil }
            return b[0] != 0 || c[0] != 0
        }
    }
}
