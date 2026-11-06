import Foundation

/// Kademeli limit hesabı (saf).
enum TierLadder {
    /// Kullanım yüzdesi: günlük toplamın günlük limite oranı ile (varsa) dönem toplamının aylık limite oranının büyüğü.
    static func percent(dailyUsed: UInt64, dailyCap: UInt64, cycleUsed: UInt64? = nil, monthlyCap: UInt64? = nil) -> Double {
        var p = dailyCap > 0 ? Double(dailyUsed) * 100 / Double(dailyCap) : 0
        if let cycleUsed, let monthlyCap, monthlyCap > 0 {
            p = max(p, Double(cycleUsed) * 100 / Double(monthlyCap))
        }
        return p
    }

    /// Eşikler dahil (örn. %80'de tam olarak warn).
    static func level(percent: Double, config: TierLadderConfig) -> TierLevel {
        let c = config.normalized
        if percent >= Double(c.cutPercent) { return .cut }
        if percent >= Double(c.slowPercent) { return .slow }
        if percent >= Double(c.warnPercent) { return .warn }
        return .none
    }
}
