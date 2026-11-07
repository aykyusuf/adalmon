import CoreMedia
import Foundation

/// Video döngüsünün SAF zamanlama mantığı (uygulama ve ekran koruyucu ortak kullanır; AVFoundation'a dokunmaz).
///
/// - `trimStart` / `trimEnd`: indirilen videoların siyah ya da soluk giriş/çıkışını atlamak için baştan/sondan saniye.
/// - `crossfade`: çapraz geçiş süresi (sn); 0 = kapalı (sert geçiş / kesintisiz `AVPlayerLooper`).
struct LoopTiming: Equatable, Hashable, Sendable {
    var trimStart: Double
    var trimEnd: Double
    var crossfade: Double

    static let `default` = LoopTiming(trimStart: 5, trimEnd: 3, crossfade: 1.5)
    static let none = LoopTiming(trimStart: 0, trimEnd: 0, crossfade: 0)

    static let trimLimit = 0.0...30.0
    static let crossfadeLimit = 0.5...3.0
    /// Kırpma yalnızca, kalan süre en az bu kadar uzunsa uygulanır (`süre >= baştan + sondan + bu`).
    static let minimumKeptSeconds = 10.0
    /// Sonraki örnek, geçiş başlamadan bu kadar önce gizli katmanda hazırlanır (arama + ilk kare).
    static let preroll = 0.5
    /// "Hareketi Azalt" açıkken geçiş süresi.
    static let reducedMotionFade = 0.3
    /// Bundan kısa aralıkta geçiş yapılmaz (3 sn'lik bir döngüde çapraz geçiş anlamsız).
    static let minimumFadeableLength = 3.0
    /// Geçiş, aralığın en çok bu kesri kadar olabilir (iki geçiş arasında net oynatma kalsın).
    static let maximumFadeFraction = 0.25

    /// Geçersiz (NaN, negatif, sınır dışı) değerleri düzeltir. Dosyadan okunan değerlere uygulanır.
    var sanitized: LoopTiming {
        func clean(_ value: Double, _ fallback: Double) -> Double { value.isFinite ? value : fallback }
        let start = min(max(clean(trimStart, Self.default.trimStart), Self.trimLimit.lowerBound), Self.trimLimit.upperBound)
        let end = min(max(clean(trimEnd, Self.default.trimEnd), Self.trimLimit.lowerBound), Self.trimLimit.upperBound)
        let fadeValue = clean(crossfade, Self.default.crossfade)
        let fade = fadeValue <= 0 ? 0 : min(max(fadeValue, Self.crossfadeLimit.lowerBound), Self.crossfadeLimit.upperBound)
        return LoopTiming(trimStart: start, trimEnd: end, crossfade: fade)
    }

    /// Oynatılacak aralık. Süre bilinmiyorsa `isKnown == false` (kırpma ve geçiş uygulanmaz).
    struct Range: Equatable, Sendable {
        var start: Double
        var end: Double
        var isTrimmed: Bool
        var isKnown: Bool

        var length: Double { max(0, end - start) }
        var startTime: CMTime { CMTime(seconds: start, preferredTimescale: 600) }
        var endTime: CMTime { CMTime(seconds: end, preferredTimescale: 600) }
        var timeRange: CMTimeRange { CMTimeRange(start: startTime, end: endTime) }
    }

    /// Kırpılmış aralık. Kısa videoda (`süre < baştan + sondan + 10 sn`) kırpma yok sayılır.
    func range(duration: Double?) -> Range {
        guard let duration, duration.isFinite, duration > 0 else {
            return Range(start: 0, end: 0, isTrimmed: false, isKnown: false)
        }
        let t = sanitized
        let total = t.trimStart + t.trimEnd
        guard total > 0, duration >= total + Self.minimumKeptSeconds else {
            return Range(start: 0, end: duration, isTrimmed: false, isKnown: true)
        }
        return Range(start: t.trimStart, end: duration - t.trimEnd, isTrimmed: true, isKnown: true)
    }

    /// Gerçekte kullanılacak geçiş süresi (sn). 0 = geçiş yok (sert geçiş).
    func fade(in range: Range, reduceMotion: Bool) -> Double {
        let requested = sanitized.crossfade
        guard requested > 0, range.isKnown, range.length >= Self.minimumFadeableLength else { return 0 }
        let base = reduceMotion ? Self.reducedMotionFade : requested
        return min(base, range.length * Self.maximumFadeFraction)
    }

    /// Sonraki örneğin hazırlanmaya başlayacağı oynatma zamanı (sınır gözlemcisi). Süre bilinmiyorsa `nil`
    /// (yalnızca "sona geldi" bildirimine güvenilir).
    func prepareTime(in range: Range, fade: Double) -> Double? {
        guard range.isKnown else { return nil }
        return max(range.start, range.end - fade - Self.preroll)
    }

    /// Tek öğe + geçiş kapalı: kesintisiz `AVPlayerLooper(timeRange:)`. Aksi halde iki örnekli motor.
    func usesLooper(clipCount: Int) -> Bool { clipCount == 1 && sanitized.crossfade <= 0 }

    static func nextIndex(after index: Int, count: Int) -> Int {
        count > 0 ? (index + 1) % count : 0
    }
}
