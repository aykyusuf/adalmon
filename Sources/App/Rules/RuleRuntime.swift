import Foundation

/// Bir kuralın çalışma durumu (yeniden başlatmada korunur).
struct RuleRuntime: Codable, Equatable, Sendable {
    /// Tetikleyici türü + pencere uzunluğu; değişirse sayaç sıfırlanır.
    var signature: String
    /// Sabit pencere: ilk kullanımda başlar.
    var windowStart: Date?
    /// Sabit pencere: pencerede sayılan byte (kural kapsamına göre).
    var usedBytes: UInt64 = 0
    /// Eylem şu an uygulanıyor mu? (`nil` = hayır.)
    var activeSince: Date?
    /// Kayan pencere: kaldırmadan sonra yeniden tetiklenmeyi engelleyen bekleme.
    var cooldownUntil: Date?
}
