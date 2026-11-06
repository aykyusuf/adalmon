import Foundation

/// UI için bir kuralın anlık durumu.
struct RuleStatus: Identifiable, Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case disabled
        /// Bekliyor (eşik aşılmadı).
        case idle
        /// Eylem uygulanıyor.
        case active
        /// Kayan pencere: kaldırıldı, yeniden tetiklenmeden önce bekleme.
        case cooldown
    }

    var id: UUID
    var phase: Phase
    /// Penceredeki kullanım (kural kapsamına göre).
    var usedBytes: UInt64
    var thresholdBytes: UInt64
    /// Sabit pencere: pencerenin başı / sonu (pencere henüz başlamadıysa nil).
    var windowStart: Date?
    var windowEnd: Date?
    /// Sabit pencere: pencere sonuna; kayan pencere (aktifken): en az tutma süresinin bitimine kalan saniye.
    var secondsUntilReset: TimeInterval?
    /// Eylem şu an gerçekten uygulanıyor (aktif + kapsam şu anki ağı kapsıyor + Wi-Fi'de engel değil).
    var isEnforcedNow: Bool
    /// Tüm ağlar kapsamlı engel: Wi-Fi tarafı Faz B'ye kadar uygulanamaz.
    var pendingFilterSupport: Bool
}

/// UI için kademeli limit durumu.
struct LadderStatus: Equatable, Sendable {
    var enabled = false
    var level: TierLevel = .none
    /// Kullanım yüzdesi (günlük ve varsa aylık oranın büyüğü), 0...
    var percent = 0
    var throttledApps: [String] = []
    var blockedApps: [String] = []
    var pendingFilterSupport = false
}
