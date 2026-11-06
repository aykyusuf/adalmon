import Foundation

/// Kural tetiklenince uygulanan eylem.
enum RuleAction: Codable, Equatable, Sendable {
    /// Hız sınırı (byte/sn). `nil` yön sınırsız; ikisi de boşsa eylem etkisizdir.
    case throttle(downBytesPerSec: Int?, upBytesPerSec: Int?)
    /// Mobil veride engelle (`blockedOnMobile`). Tüm ağlar kapsamı için Wi-Fi tarafı Faz B'ye kadar uygulanamaz.
    case block

    var isBlock: Bool {
        if case .block = self { return true }
        return false
    }

    var isThrottle: Bool { !isBlock }

    /// Hız sınırı eylemi için filtreye gidecek `AppLimit`; engelleme ya da boş sınır için `nil`.
    func limit(scope: NetworkScope) -> AppLimit? {
        guard case .throttle(let down, let up) = self else { return nil }
        let l = AppLimit(downBytesPerSec: down, upBytesPerSec: up, onlyOnMobile: scope == .mobileOnly)
        return l.hasCap ? l : nil
    }
}
