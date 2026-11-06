import Foundation

/// Veritabanı satırlarından çubuk listesi üretir (saf; testlenebilir).
enum HistoryBuilder {
    private static let locale = Locale(identifier: "tr_TR")

    // MARK: Saatlik (Gün)

    /// `dayStart` (yerel gün başı) ile başlayan 24 saatlik çubuk.
    static func hourBars(points: [UsageStore.HourPoint], dayStart: Date, calendar: Calendar = .current) -> [HistoryBar] {
        let start = Int(dayStart.timeIntervalSince1970)
        var byHour: [Int: UsageStore.HourPoint] = [:]
        for p in points { byHour[p.hour] = p }
        return (0..<24).map { i in
            let hour = start + i * 3_600
            let p = byHour[hour]
            let next = (i + 1) % 24
            return HistoryBar(id: "h\(i)", target: .hour(hour),
                              label: String(format: "%02d:00 – %02d:00", i, next),
                              axisLabel: i % 3 == 0 ? String(format: "%02d", i) : nil,
                              mobile: p?.mobileBytes ?? 0, other: p?.otherBytes ?? 0)
        }
    }

    // MARK: Günlük (Hafta / Ay)

    /// `end` gününü de içeren, eskiden yeniye `count` gün anahtarı.
    static func dayKeys(count: Int, endingAt end: Date) -> [String] {
        var keys: [String] = []
        for i in stride(from: count - 1, through: 0, by: -1) {
            let key = UsageStore.dayKey(end.addingTimeInterval(-Double(i) * 86_400))
            if keys.last != key { keys.append(key) }
        }
        return keys
    }

    static func dayBars(points: [UsageStore.DayPoint], keys: [String]) -> [HistoryBar] {
        var byDay: [String: UsageStore.DayPoint] = [:]
        for p in points { byDay[p.day] = p }
        let weekly = keys.count <= 7
        return keys.enumerated().map { index, key in
            let p = byDay[key]
            let date = date(fromDayKey: key)
            let axis: String? = if weekly {
                dayLabel(date, weekday: true)
            } else if (keys.count - 1 - index) % 5 == 0 {
                dayLabel(date, weekday: false)
            } else {
                nil
            }
            return HistoryBar(id: key, target: .day(key), label: longDayLabel(date), axisLabel: axis,
                              mobile: p?.mobileBytes ?? 0, other: p?.otherBytes ?? 0)
        }
    }

    // MARK: Etiketler

    static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return UsageStore.keyCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func style(calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// "5 Kas" ya da hafta için "Per 5".
    static func dayLabel(_ date: Date?, weekday: Bool) -> String {
        guard let date else { return "" }
        let cal = UsageStore.keyCalendar
        if weekday { return date.formatted(style(calendar: cal).weekday(.abbreviated).day()) }
        return date.formatted(style(calendar: cal).day().month(.abbreviated))
    }

    static func longDayLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(style(calendar: UsageStore.keyCalendar).weekday(.wide).day().month(.wide))
    }

    /// Hafta/Ay başlığı: "30 Eki – 5 Kas".
    static func rangeTitle(keys: [String]) -> String {
        guard let first = keys.first, let last = keys.last else { return "" }
        return "\(dayLabel(date(fromDayKey: first), weekday: false)) – \(dayLabel(date(fromDayKey: last), weekday: false))"
    }

    /// Gün başlığı: "Bugün", "Dün" ya da "Perşembe 5 Kasım".
    static func dayTitle(dayStart: Date, offset: Int) -> String {
        switch offset {
        case 0: "Bugün"
        case 1: "Dün"
        default: dayStart.formatted(style(calendar: .current).weekday(.wide).day().month(.wide))
        }
    }
}
