import Foundation

/// Kuralı tetikleyen koşul. Süre dakika cinsindendir; byte eşiği giriş + çıkış toplamıdır.
enum RuleTrigger: Codable, Equatable, Sendable {
    /// Kayan pencere: "son `minutes` dakikada `bytes` ya da daha fazlası kullanıldı".
    case rolling(minutes: Int, bytes: UInt64)
    /// Sabit pencere: pencere ilk kullanımda başlar, `minutes` sonra biter; sayaç sıfırlanır ve eylem kalkar.
    case fixedWindow(minutes: Int, bytes: UInt64)

    /// Kayan pencere için üst sınır (halka tamponu kapasitesi).
    static let maxRollingMinutes = 720
    /// Sabit pencere için üst sınır (31 gün).
    static let maxFixedMinutes = 31 * 24 * 60

    static func fixedWindow(hours: Int, bytes: UInt64) -> RuleTrigger {
        .fixedWindow(minutes: hours * 60, bytes: bytes)
    }

    var isFixedWindow: Bool {
        if case .fixedWindow = self { return true }
        return false
    }

    /// Geçerli aralığa sıkıştırılmış pencere uzunluğu (dakika).
    var windowMinutes: Int {
        switch self {
        case .rolling(let m, _): min(max(1, m), Self.maxRollingMinutes)
        case .fixedWindow(let m, _): min(max(1, m), Self.maxFixedMinutes)
        }
    }

    var thresholdBytes: UInt64 {
        switch self {
        case .rolling(_, let b), .fixedWindow(_, let b): max(1, b)
        }
    }

    /// Sayaç durumunu sıfırlamayı gerektiren değişiklikleri ayırt eder (eşik değişimi sıfırlamaz).
    var signature: String { "\(isFixedWindow ? "fixed" : "rolling"):\(windowMinutes)" }
}
