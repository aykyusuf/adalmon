import Foundation

/// Faturalama dönemi bütçesi ve tahminler (UI doğrudan gösterir).
struct BudgetSnapshot: Equatable, Sendable {
    /// Dönem başı (gün başlangıcı) ve bir sonraki dönemin başı.
    var cycleStart: Date
    var nextCycleStart: Date
    /// Bugün dahil dönem kullanımı (mobil, fiziksel arayüz sayaçları).
    var cycleUsedBytes: UInt64
    var todayUsedBytes: UInt64
    var monthlyCapBytes: UInt64?
    /// `monthlyCap - cycleUsed` (şu an), sınırlı 0.
    var remainingBytes: UInt64?
    /// Bugün dahil dönem bitimine kalan gün sayısı (≥ 1).
    var daysLeft: Int
    /// Dinamik günlük bütçe = (aylık limit − bugünden önceki kullanım) / kalan gün (bugün dahil). Gün içinde sabittir.
    var dynamicDailyBudgetBytes: UInt64?
    /// Bugünkü etkin limit: günlük limit ile dinamik bütçenin küçüğü.
    var effectiveDailyCapBytes: UInt64
    /// Bugünkü etkin limitten kalan.
    var todayRemainingBytes: UInt64
    /// Son 15 dk hızına (B/sn) göre GÜNLÜK limitin dolma tahmini.
    var etaRecentRate: CapETA
    /// Bugünkü ortalama hıza göre GÜNLÜK limitin dolma tahmini.
    var etaAverageRate: CapETA
    /// Aylık limit varsa: aynı iki hızla dinamik günlük bütçenin dolma tahmini (yoksa nil).
    var etaBudgetRecentRate: CapETA?
    var etaBudgetAverageRate: CapETA?
    /// Dönem sonu projeksiyonu (şimdiye kadarki ortalama günlük hızla); dönemin ilk günü için nil.
    var projectedCycleBytes: UInt64?
}

/// Grafik noktası: o ana kadar kümülatif byte.
struct CumulativePoint: Equatable, Sendable {
    var date: Date
    var bytes: UInt64
}
