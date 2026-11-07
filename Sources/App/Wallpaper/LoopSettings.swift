import Foundation

/// Kullanıcının döngü ayarları (duvar kâğıdı; ekran koruyucu oynatma listesi JSON'u üzerinden aynısını kullanır).
struct LoopSettings: Codable, Equatable, Hashable, Sendable {
    /// Baştan atlanacak saniye (indirilen videoların siyah / soluk girişi).
    var trimStart: Double = LoopTiming.default.trimStart
    /// Sondan kesilecek saniye.
    var trimEnd: Double = LoopTiming.default.trimEnd
    var transition: LoopTransition = .crossfade
    /// Çapraz geçiş süresi (sn); geçiş kapalıyken de değeri saklanır.
    var crossfadeSeconds: Double = LoopTiming.default.crossfade

    /// Motorun ve oynatma listesi JSON'unun kullandığı biçim (kapalıysa `crossfade == 0`).
    var timing: LoopTiming {
        LoopTiming(trimStart: trimStart, trimEnd: trimEnd, crossfade: transition == .crossfade ? crossfadeSeconds : 0).sanitized
    }
}

extension LoopSettings {
    /// Eski kayıtlarda olmayan ya da bozuk alanlar varsayılana düşer (kayıtlı ayarlar asla silinmez).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LoopTiming.default
        trimStart = (try? c.decodeIfPresent(Double.self, forKey: .trimStart)) ?? d.trimStart
        trimEnd = (try? c.decodeIfPresent(Double.self, forKey: .trimEnd)) ?? d.trimEnd
        transition = (try? c.decodeIfPresent(LoopTransition.self, forKey: .transition)) ?? .crossfade
        crossfadeSeconds = (try? c.decodeIfPresent(Double.self, forKey: .crossfadeSeconds)) ?? d.crossfade
        let clean = LoopTiming(trimStart: trimStart, trimEnd: trimEnd, crossfade: crossfadeSeconds).sanitized
        trimStart = clean.trimStart
        trimEnd = clean.trimEnd
        crossfadeSeconds = clean.crossfade > 0 ? clean.crossfade : d.crossfade
    }
}
