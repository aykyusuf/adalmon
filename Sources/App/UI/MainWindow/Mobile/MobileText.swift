import Foundation

/// Mobil veri sayfasının saf metin biçimlendiricileri (Türkçe).
enum MobileText {
    private static let locale = Locale(identifier: "tr_TR")

    /// "21:40"
    static func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// "1 Kasım": gün anahtarı takviminde (GMT) gün ve ay.
    static func day(_ date: Date) -> String {
        let cal = UsageStore.keyCalendar
        return date.formatted(Date.FormatStyle(locale: locale, calendar: cal, timeZone: cal.timeZone).day().month(.wide))
    }

    /// Limit dolma tahmini cümlesi. `basis`: "Bu hızla" / "Gün ortalamasıyla" gibi ön ek.
    static func eta(_ eta: CapETA, basis: String, limitName: String) -> String {
        switch eta {
        case .reached: "\(limitName) doldu"
        case .at(let date): "\(basis) \(limitName.lowercased()) \(clock(date)) civarında dolar"
        case .notToday: "\(basis) \(limitName.lowercased()) bugün dolmaz"
        case .noData: "\(basis) tahmin için yeterli veri yok"
        }
    }

    /// "1 gün", "24 gün" (kalan gün sayısı).
    static func days(_ n: Int) -> String { "\(n) gün" }
}
