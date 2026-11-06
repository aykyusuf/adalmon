import Foundation

/// Grafikteki tek çubuk: bir saat ya da bir gün; mobil ve Wi-Fi/diğer baytlar.
struct HistoryBar: Identifiable, Equatable, Sendable {
    enum Target: Equatable, Sendable {
        /// Saat başının epoch saniyesi.
        case hour(Int)
        /// `yyyy-MM-dd` gün anahtarı.
        case day(String)
        /// `yyyy-MM-dd` aralığı (ikisi dahil); yalnızca rapor kartındaki uygulama satırları için.
        case days(from: String, to: String)
    }

    let id: String
    let target: Target
    /// Ayrıntı başlığı: "14:00 – 15:00" ya da "5 Kasım Perşembe".
    let label: String
    /// Eksende gösterilecek kısa etiket; nil ise bu çubukta etiket yok.
    let axisLabel: String?
    var mobile: UInt64
    var other: UInt64

    var total: UInt64 { mobile + other }
}
