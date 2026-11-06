import Foundation

/// Uygulama detay panelinin depodan okunan verisi. Seçim değişince bir kez yüklenir (saniyelik güncelleme yok).
struct AppDetail: Equatable, Sendable {
    struct Day: Identifiable, Equatable, Sendable {
        /// `yyyy-MM-dd` gün anahtarı.
        var id: String
        /// Kısa gün adı ("Pzt").
        var label: String
        var mobile: UInt64
        var other: UInt64
        var isToday: Bool

        var total: UInt64 { mobile + other }
    }

    struct Hour: Identifiable, Equatable, Sendable {
        var start: Date
        var mobile: UInt64
        var other: UInt64

        var id: Int { Int(start.timeIntervalSince1970) }
        var total: UInt64 { mobile + other }
    }

    /// Bugün dahil son 7 gün (verisi olmayan günler sıfırla doldurulur).
    var days: [Day]
    /// Bugünün saatlik kayıtları (kayıt olmayan saatler yoktur).
    var hours: [Hour]
    /// Bugünün başlangıcı (gün anahtarı takvimine göre).
    var dayStart: Date
    /// Saatlik kaydın ilk saat başı (tüm uygulamalar için); yoksa hiç saatlik kayıt yazılmamış demektir.
    var hourlySince: Date? = nil
    var domainsToday: [UsageStore.DomainBytes]
    var domains7d: [UsageStore.DomainBytes]

    /// Saatlik grafik boşken gösterilecek açıklama. Saatlik kayıt gün ortasında başlamış olabilir
    /// (günlük toplam o saatten öncesini içerir, saatlik kayıt içermez); bu durum "kayıt yok" gibi okunmamalı.
    func hourlyEmptyMessage(hasTraffic: Bool, calendar: Calendar = UsageStore.keyCalendar) -> String {
        guard hasTraffic, let since = hourlySince, since >= dayStart else { return "Bugün için saatlik kayıt yok" }
        let time = since.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "tr_TR"),
                                                    calendar: calendar, timeZone: calendar.timeZone))
        return "Saatlik kayıt \(time) itibarıyla tutuluyor; bu uygulama o saatten beri trafik üretmedi."
    }

    var weekTotal: UInt64 { days.reduce(0) { $0 + $1.total } }
}
