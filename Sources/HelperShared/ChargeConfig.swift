import Foundation

/// Şarj sınırı yapılandırması. Yardımcı diske yazar; yalnızca doğrulanmış değerler kabul edilir.
struct ChargeConfig: Codable, Equatable, Sendable {
    var enabled = false
    /// 50...100, 5'in katı. 100 = sınır yok.
    var limit = 80
    /// Seyir: şarj yalnızca pil bu yüzdenin ALTINA inince yeniden başlar.
    var sailingFloor = 75
    /// "Şarjı şimdi tamamla": sınır geçici olarak yok sayılır. Pil dolunca, fişten çıkınca ya da süre dolunca biter.
    var topUpStartedAt: Date?

    static let off = ChargeConfig()

    var isTopUp: Bool { topUpStartedAt != nil }

    /// Geçerli mi (aralık, adım, seyir aralığı, bekçi tabanı).
    var isValid: Bool { Self.validate(limit: limit, sailingFloor: sailingFloor) == nil }

    static func validate(limit: Int, sailingFloor: Int) -> HelperErrorCode? {
        guard HelperConstants.limitRange.contains(limit), limit % HelperConstants.limitStep == 0 else { return .outOfRange }
        guard limit < 100 else { return nil } // sınır yok: seyir alanı kullanılmaz
        guard sailingFloor >= HelperConstants.hardFloorPercent,
              sailingFloor < limit,
              limit - sailingFloor <= HelperConstants.maxSailingGap else { return .outOfRange }
        return nil
    }
}
