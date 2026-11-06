import Foundation

/// Bir dönemin raporunu veritabanından okur. Günlük tablolardan (`iface_daily`, `usage`) okuduğu için saatlik kaydı
/// olmayan eski günler de çalışır; `UsageStore` actor olduğundan ana iş parçacığını bloklamaz.
enum HistoryReportLoader {
    static let appLimit = 6
    static let domainLimit = 6

    static func load(period: HistoryReportPeriod, store: UsageStore) async -> HistoryReport {
        let totals = await store.dailyTotals(fromDay: period.fromDay, toDay: period.toDay)
        let previous = await store.dailyTotals(fromDay: period.previousFromDay, toDay: period.previousToDay)
        let apps = await store.topApps(fromDay: period.fromDay, toDay: period.toDay, limit: appLimit)
        let domains = await store.topDomains(fromDay: period.fromDay, toDay: period.toDay, limit: domainLimit)
        let attributed = await store.attributedBytes(fromDay: period.fromDay, toDay: period.toDay)
        return HistoryReport(
            period: period,
            mobile: totals.reduce(0) { $0 + $1.mobileBytes },
            other: totals.reduce(0) { $0 + $1.otherBytes },
            previousTotal: previous.reduce(0) { $0 + $1.mobileBytes + $1.otherBytes },
            apps: apps.map { HistoryAppBytes(app: $0.app, bytes: $0.bytes, mobile: $0.mobileBytes) },
            domains: domains.map { HistoryDomainBytes(name: $0.name, bytes: $0.bytes) },
            attributed: attributed)
    }
}
