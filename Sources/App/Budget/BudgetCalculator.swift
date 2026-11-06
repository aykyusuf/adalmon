import Foundation

/// Fatura dönemi, bütçe ve tahmin hesabı. Saf ve test edilir; `Calendar` ve `now` dışarıdan verilir.
///
/// Gün anahtarları `UsageStore` ile aynı biçimde (`yyyy-MM-dd`) üretilir; hangi saat dilimine göre olacağını
/// verilen `calendar` belirler (`UsageStore.keyCalendar`).
enum BudgetCalculator {
    /// `yyyy-MM-dd` (verilen takvimin saat diliminde).
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `startDay` ayda yoksa ayın son gününe düşer (örn. 31 → şubat 28/29).
    private static func start(year: Int, month: Int, startDay: Int, calendar: Calendar) -> Date {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        return calendar.date(from: DateComponents(year: year, month: month, day: min(max(1, startDay), count))) ?? first
    }

    /// `date`'i içeren dönemin başlangıcı (gün başı).
    static func cycleStart(containing date: Date, startDay: Int, calendar: Calendar) -> Date {
        let c = calendar.dateComponents([.year, .month], from: date)
        let thisMonth = start(year: c.year ?? 1970, month: c.month ?? 1, startDay: startDay, calendar: calendar)
        if calendar.startOfDay(for: date) >= thisMonth { return thisMonth }
        let prev = calendar.date(byAdding: .month, value: -1, to: calendar.date(from: DateComponents(year: c.year, month: c.month, day: 1)) ?? date) ?? date
        let p = calendar.dateComponents([.year, .month], from: prev)
        return start(year: p.year ?? 1970, month: p.month ?? 1, startDay: startDay, calendar: calendar)
    }

    /// `cycleStart`'tan sonraki dönemin başlangıcı.
    static func nextCycleStart(after cycleStart: Date, startDay: Int, calendar: Calendar) -> Date {
        let c = calendar.dateComponents([.year, .month], from: cycleStart)
        let firstOfMonth = calendar.date(from: DateComponents(year: c.year, month: c.month, day: 1)) ?? cycleStart
        let next = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) ?? cycleStart
        let n = calendar.dateComponents([.year, .month], from: next)
        return start(year: n.year ?? 1970, month: n.month ?? 1, startDay: startDay, calendar: calendar)
    }

    /// Limit dolma tahmini. `rate` byte/sn.
    static func capETA(used: UInt64, cap: UInt64, rate: Double, now: Date, endOfDay: Date) -> CapETA {
        guard cap > 0 else { return .noData }
        if used >= cap { return .reached }
        guard rate > 0, rate.isFinite else { return .noData }
        let eta = now.addingTimeInterval(Double(cap - used) / rate)
        return eta < endOfDay ? .at(eta) : .notToday
    }

    /// - Parameters:
    ///   - cycleUsedBeforeToday: Dönem başından dünün sonuna kadar mobil toplam (`iface_daily`, bir kez okunur).
    ///   - todayUsed: Bugünkü mobil toplam (bellekteki canlı sayaç).
    ///   - recentRate: Son 15 dk'nın mobil hızı (B/sn).
    static func snapshot(now: Date, startDay: Int, monthlyCapBytes: UInt64?, dailyCapBytes: UInt64,
                         cycleUsedBeforeToday: UInt64, todayUsed: UInt64, recentRate: Double,
                         calendar: Calendar) -> BudgetSnapshot {
        let today = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let cycleStart = cycleStart(containing: now, startDay: startDay, calendar: calendar)
        let next = nextCycleStart(after: cycleStart, startDay: startDay, calendar: calendar)
        let daysLeft = max(1, calendar.dateComponents([.day], from: today, to: next).day ?? 1)
        let cycleDays = max(1, calendar.dateComponents([.day], from: cycleStart, to: next).day ?? 30)
        let elapsedDays = max(0, calendar.dateComponents([.day], from: cycleStart, to: today).day ?? 0)
        let cycleUsed = cycleUsedBeforeToday &+ todayUsed

        var remaining: UInt64?
        var dynamic: UInt64?
        if let cap = monthlyCapBytes {
            remaining = cap > cycleUsed ? cap - cycleUsed : 0
            let beforeToday = cap > cycleUsedBeforeToday ? cap - cycleUsedBeforeToday : 0
            dynamic = beforeToday / UInt64(daysLeft)
        }
        let effectiveCap = min(dailyCapBytes, dynamic ?? .max)
        let avgRate = Double(todayUsed) / max(60, now.timeIntervalSince(today))
        var projected: UInt64?
        if elapsedDays > 0 {
            projected = UInt64(Double(cycleUsedBeforeToday) / Double(elapsedDays) * Double(cycleDays))
        }
        return BudgetSnapshot(
            cycleStart: cycleStart, nextCycleStart: next,
            cycleUsedBytes: cycleUsed, todayUsedBytes: todayUsed,
            monthlyCapBytes: monthlyCapBytes, remainingBytes: remaining,
            daysLeft: daysLeft, dynamicDailyBudgetBytes: dynamic,
            effectiveDailyCapBytes: effectiveCap,
            todayRemainingBytes: effectiveCap > todayUsed ? effectiveCap - todayUsed : 0,
            etaRecentRate: capETA(used: todayUsed, cap: dailyCapBytes, rate: recentRate, now: now, endOfDay: endOfDay),
            etaAverageRate: capETA(used: todayUsed, cap: dailyCapBytes, rate: avgRate, now: now, endOfDay: endOfDay),
            etaBudgetRecentRate: dynamic.map { capETA(used: todayUsed, cap: $0, rate: recentRate, now: now, endOfDay: endOfDay) },
            etaBudgetAverageRate: dynamic.map { capETA(used: todayUsed, cap: $0, rate: avgRate, now: now, endOfDay: endOfDay) },
            projectedCycleBytes: projected)
    }

    /// Bugünün kümülatif serisi (grafik için). `hourly`: saat başı epoch (sn) → o saatin byte'ı.
    /// Noktalar gün başında 0'dan başlar, her tam saatin sonunda bir nokta içerir; son nokta `now`'dadır.
    static func cumulativeSeries(hourly: [Int: UInt64], now: Date, calendar: Calendar) -> [CumulativePoint] {
        let dayStart = calendar.startOfDay(for: now)
        var points = [CumulativePoint(date: dayStart, bytes: 0)]
        var total: UInt64 = 0
        var hourStart = dayStart
        while hourStart < now {
            guard let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { break }
            // Saatlik anahtarlar epoch saat başıdır; yerel saat başı yarım saatlik dilimlerde (ör. +05:30) onlarla
            // hizalanmaz → anahtarın başladığı yerel saat aralığına eklenir. DST'de 23/25 saatlik gün doğal çıkar.
            let lo = Int(hourStart.timeIntervalSince1970), hi = Int(hourEnd.timeIntervalSince1970)
            for (h, v) in hourly where h >= lo && h < hi { total &+= v }
            points.append(CumulativePoint(date: min(hourEnd, now), bytes: total))
            hourStart = hourEnd
        }
        return points
    }
}
