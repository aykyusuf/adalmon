import Foundation

/// Genel bakışın SQLite'tan okuduğu, sık değişmeyen bugün/dün verileri.
struct OverviewDayStats: Equatable, Sendable {
    /// Dünün toplamı (mobil + diğer); kayıt yoksa nil.
    var yesterdayTotal: UInt64?
    /// Bugün uygulamalara yazılan ve diske işlenmiş indirme / yükleme (yeniden başlatma sonrası ↓↑ için taban).
    var storedDown: UInt64 = 0
    var storedUp: UInt64 = 0
}
