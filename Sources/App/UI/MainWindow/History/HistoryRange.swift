import Foundation

/// Geçmiş sayfasının zaman aralığı.
enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case day, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Gün"
        case .week: "Hafta"
        case .month: "Ay"
        }
    }

    /// Günlük çubuk sayısı (`.day` saatlik 24 çubuk gösterir).
    var dayCount: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        }
    }

    /// Geri gidilebilecek en çok sayfa: saatlik kayıtlar 60 gün tutulur.
    var maxOffset: Int {
        switch self {
        case .day: UsageStore.hourlyRetentionDays - 1
        case .week: 52
        case .month: 24
        }
    }
}
