import Foundation

/// `OverviewDayStats`'ı veritabanından okur. Sayfa açılınca ve seyrek aralıklarla çağrılır; her saniye değil.
enum OverviewDayLoader {
    static func load(store: UsageStore, now: Date = .now) async -> OverviewDayStats {
        let todayKey = UsageStore.dayKey(now)
        let yesterdayKey = UsageStore.dayKey(now.addingTimeInterval(-86_400))
        let yesterday = await store.dailyTotals(fromDay: yesterdayKey, toDay: yesterdayKey).first
        let rows = await store.rows(day: todayKey)
        var stats = OverviewDayStats()
        stats.yesterdayTotal = yesterday.map { $0.mobileBytes + $0.otherBytes }
        for row in rows {
            stats.storedDown += row.bytesIn
            stats.storedUp += row.bytesOut
        }
        return stats
    }
}
