import Foundation

/// Rapor `.task(id:)` anahtarı: dönem ya da yenileme sayacı değişince rapor yeniden okunur.
struct HistoryReportRequest: Equatable {
    var period: HistoryReportPeriod
    var reload: Int
}
