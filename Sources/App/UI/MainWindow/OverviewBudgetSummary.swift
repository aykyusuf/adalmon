import Foundation

/// Mobil kota mini kartının metin ve oran hesapları (saf).
enum OverviewBudgetSummary {
    /// Günlük kullanım oranı (etkin günlük limite göre), 0...1.
    static func todayFraction(_ b: BudgetSnapshot) -> Double {
        guard b.effectiveDailyCapBytes > 0 else { return 0 }
        return min(1, Double(b.todayUsedBytes) / Double(b.effectiveDailyCapBytes))
    }

    /// Dönem kullanım oranı (aylık limit yoksa nil), 0...1.
    static func cycleFraction(_ b: BudgetSnapshot) -> Double? {
        guard let cap = b.monthlyCapBytes, cap > 0 else { return nil }
        return min(1, Double(b.cycleUsedBytes) / Double(cap))
    }

    /// Günlük bütçenin dolma tahmini cümlesi; veri yoksa nil. Günlük limit ile (varsa) dinamik bütçeden daha erken olan seçilir.
    static func etaText(_ b: BudgetSnapshot, calendar: Calendar = .current) -> String? {
        let candidates = [b.etaRecentRate, b.etaBudgetRecentRate].compactMap { $0 }
        if candidates.contains(.reached) { return "Bugünkü bütçe doldu" }
        let times = candidates.compactMap { eta -> Date? in
            if case .at(let date) = eta { date } else { nil }
        }
        if let first = times.min() {
            return "Bu hızla " + first.formatted(.dateTime.hour().minute().locale(Locale(identifier: "tr_TR"))) + " civarı dolar"
        }
        if candidates.contains(.notToday) { return "Bu hızla bugün dolmaz" }
        return nil
    }

    /// "12 gün kaldı" ya da "son gün".
    static func daysText(_ b: BudgetSnapshot) -> String {
        b.daysLeft <= 1 ? "dönemin son günü" : "\(b.daysLeft) gün kaldı"
    }
}
