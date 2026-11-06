import Foundation

/// Bir aralığın grafik verisini veritabanından okur. `UsageStore` bir actor olduğundan sorgular ana iş parçacığında çalışmaz.
enum HistoryLoader {
    static func load(range: HistoryRange, offset: Int, store: UsageStore, now: Date = .now) async -> HistoryContent {
        switch range {
        case .day: await loadDay(offset: offset, store: store, now: now)
        case .week, .month: await loadDays(range: range, offset: offset, store: store, now: now)
        }
    }

    private static func loadDay(offset: Int, store: UsageStore, now: Date) async -> HistoryContent {
        let cal = UsageStore.keyCalendar
        let anchor = cal.date(byAdding: .day, value: -offset, to: now) ?? now
        let dayStart = cal.startOfDay(for: anchor)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let points = await store.interfaceHourly(from: Int(dayStart.timeIntervalSince1970), to: Int(dayEnd.timeIntervalSince1970))
        return HistoryContent(bars: HistoryBuilder.hourBars(points: points, dayStart: dayStart, calendar: cal),
                              periodTitle: HistoryBuilder.dayTitle(dayStart: dayStart, offset: offset))
    }

    private static func loadDays(range: HistoryRange, offset: Int, store: UsageStore, now: Date) async -> HistoryContent {
        let end = now.addingTimeInterval(-Double(offset * range.dayCount) * 86_400)
        let keys = HistoryBuilder.dayKeys(count: range.dayCount, endingAt: end)
        guard let first = keys.first, let last = keys.last else { return .empty }
        let points = await store.dailyTotals(fromDay: first, toDay: last)
        return HistoryContent(bars: HistoryBuilder.dayBars(points: points, keys: keys),
                              periodTitle: HistoryBuilder.rangeTitle(keys: keys))
    }
}
