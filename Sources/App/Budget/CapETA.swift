import Foundation

/// Günlük limit dolma tahmini.
enum CapETA: Equatable, Sendable {
    /// Limit zaten doldu.
    case reached
    /// Bu hızla limit bu zamanda dolar (bugün içinde).
    case at(Date)
    /// Bu hızla bugün dolmaz.
    case notToday
    /// Hız sıfır / veri yok.
    case noData
}
