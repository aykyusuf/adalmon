import Foundation

/// "Bugün" kartının gösterdiği değerler.
struct TodaySummary: Equatable, Sendable {
    var total: UInt64
    var down: UInt64
    var up: UInt64
    var mobile: UInt64
    var wifi: UInt64
    var yesterday: UInt64?

    /// Toplam: fiziksel arayüz sayaçları (açılışta veritabanından yüklenir). ↓↑: oturum sayacı ile diske işlenmiş
    /// uygulama toplamının büyüğü; böylece yeniden başlatmadan sonra da bugünün tamamını yansıtır.
    static func make(data: PanelData, stats: OverviewDayStats) -> TodaySummary {
        TodaySummary(total: data.mobileToday + data.wifiToday,
                     down: max(data.downToday, stats.storedDown),
                     up: max(data.upToday, stats.storedUp),
                     mobile: data.mobileToday, wifi: data.wifiToday,
                     yesterday: stats.yesterdayTotal)
    }

    /// Bugünkü toplamın dünkü toplama oranı (dün kaydı yoksa nil).
    var versusYesterday: Double? {
        guard let yesterday, yesterday > 0 else { return nil }
        return Double(total) / Double(yesterday)
    }
}
