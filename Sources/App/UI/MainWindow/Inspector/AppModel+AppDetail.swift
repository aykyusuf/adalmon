import Foundation

extension AppModel {
    /// Bir uygulamanın detay verisini depodan okur: 7 günlük seri, bugünün saatlik serisi, alan adları.
    /// Yalnızca çağrıldığında çalışır (seçim değişince); düzenli yoklama yoktur.
    func appDetail(for app: String, now: Date = .now) async -> AppDetail {
        let cal = UsageStore.keyCalendar
        let today = cal.startOfDay(for: now)
        let first = cal.date(byAdding: .day, value: -6, to: today) ?? today
        let fromKey = BudgetCalculator.dayKey(first, calendar: cal)
        let todayKey = BudgetCalculator.dayKey(today, calendar: cal)
        let hourFrom = Int(today.timeIntervalSince1970)

        let series = await store.dailySeries(app: app, fromDay: fromKey, toDay: todayKey)
        let hourly = await store.hourlySeries(app: app, from: hourFrom, to: hourFrom + 86_400)
        let domainsToday = await store.topDomains(app: app, fromDay: todayKey, toDay: todayKey, limit: 12)
        let domains7d = await store.topDomains(app: app, fromDay: fromKey, toDay: todayKey, limit: 12)

        let firstHour = await store.firstHourlyRecord()

        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "tr_TR"),
                                     calendar: cal, timeZone: cal.timeZone).weekday(.abbreviated)
        let byDay = Dictionary(series.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let days: [AppDetail.Day] = (0..<7).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: offset, to: first) else { return nil }
            let key = BudgetCalculator.dayKey(date, calendar: cal)
            let point = byDay[key]
            return AppDetail.Day(id: key, label: date.formatted(style), mobile: point?.mobileBytes ?? 0,
                                 other: point?.otherBytes ?? 0, isToday: key == todayKey)
        }
        let hours = hourly.map {
            AppDetail.Hour(start: Date(timeIntervalSince1970: TimeInterval($0.hour)), mobile: $0.mobileBytes, other: $0.otherBytes)
        }
        return AppDetail(days: days, hours: hours, dayStart: today, hourlySince: firstHour.map { Date(timeIntervalSince1970: TimeInterval($0)) }, domainsToday: domainsToday, domains7d: domains7d)
    }
}
