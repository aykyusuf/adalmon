import Foundation

/// Raporun kapsadığı gün aralığı (`yyyy-MM-dd`, ikisi dahil) ve karşılaştırılacak önceki aynı uzunluktaki aralık.
struct HistoryReportPeriod: Equatable, Sendable {
    let fromDay: String
    let toDay: String
    /// "Bugün", "Dün", "Son 7 gün", "Bu ay", "30 Eki – 5 Kas" vb.
    let title: String
    /// Tarih aralığı metni: "6 Kasım Cuma" ya da "30 Eki – 5 Kas".
    let subtitle: String
    let dayCount: Int
    /// Aralık bugünü kapsıyor mu (bugün henüz bitmediği için tek günlük karşılaştırma yanıltıcı olur).
    let includesToday: Bool
    let previousFromDay: String
    let previousToDay: String

    /// Önceki dönemle yüzde karşılaştırması anlamlı mı? Bitmemiş tek gün, dünün tamamıyla kıyaslanmaz.
    var isComparable: Bool { !(dayCount == 1 && includesToday) }

    /// Geçmiş sayfasının durumundan (aralık, sayfa, takvim ayı seçimi) rapor dönemini üretir.
    /// `calendarMonth` yalnızca `.month` + sayfa 0 iken geçerlidir: ayın 1'inden bugüne.
    static func make(range: HistoryRange, offset: Int, calendarMonth: Bool = false, now: Date = .now) -> HistoryReportPeriod {
        let cal = UsageStore.keyCalendar
        let todayKey = UsageStore.dayKey(now, calendar: cal)
        switch range {
        case .day:
            let anchor = cal.date(byAdding: .day, value: -offset, to: now) ?? now
            let dayStart = cal.startOfDay(for: anchor)
            let key = UsageStore.dayKey(dayStart, calendar: cal)
            return build(from: key, to: key, title: HistoryBuilder.dayTitle(dayStart: dayStart, offset: offset),
                         subtitle: HistoryBuilder.longDayLabel(dayStart), todayKey: todayKey)
        case .week, .month:
            let end = now.addingTimeInterval(-Double(offset * range.dayCount) * 86_400)
            let keys = HistoryBuilder.dayKeys(count: range.dayCount, endingAt: end)
            guard let first = keys.first, let last = keys.last else {
                return build(from: todayKey, to: todayKey, title: "", subtitle: "", todayKey: todayKey)
            }
            if calendarMonth, range == .month, offset == 0 {
                let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
                let from = UsageStore.dayKey(monthStart, calendar: cal)
                return build(from: from, to: todayKey, title: "Bu ay",
                             subtitle: HistoryBuilder.rangeTitle(keys: [from, todayKey]), todayKey: todayKey)
            }
            let title = offset == 0 ? (range == .week ? "Son 7 gün" : "Son 30 gün") : HistoryBuilder.rangeTitle(keys: keys)
            return build(from: first, to: last, title: title, subtitle: HistoryBuilder.rangeTitle(keys: keys), todayKey: todayKey)
        }
    }

    private static func build(from: String, to: String, title: String, subtitle: String, todayKey: String) -> HistoryReportPeriod {
        let cal = UsageStore.keyCalendar
        let start = HistoryBuilder.date(fromDayKey: from)
        let end = HistoryBuilder.date(fromDayKey: to)
        let span = (start != nil && end != nil) ? (cal.dateComponents([.day], from: start!, to: end!).day ?? 0) : 0
        let count = max(1, span + 1)
        // Önceki dönem: hemen öncesindeki aynı uzunlukta aralık.
        var prevFrom = from
        var prevTo = from
        if let start, let prevEnd = cal.date(byAdding: .day, value: -1, to: start),
           let prevStart = cal.date(byAdding: .day, value: -(count - 1), to: prevEnd) {
            prevTo = UsageStore.dayKey(prevEnd, calendar: cal)
            prevFrom = UsageStore.dayKey(prevStart, calendar: cal)
        }
        return HistoryReportPeriod(fromDay: from, toDay: to, title: title, subtitle: subtitle, dayCount: count,
                                   includesToday: to >= todayKey, previousFromDay: prevFrom, previousToDay: prevTo)
    }
}
