import Foundation

/// Oturumun elle verilen küçült/aç kararı (yalnızca bellekte; oturumlar zaten geçici).
enum SessionDockOverride: Equatable, Sendable {
    /// Kullanıcı küçülttü: oturum tekrar çalışmaya başlayana kadar küçük kalır.
    case minimized
    /// Kullanıcı (otomatik küçülmüş) oturumu açtı: boşta sayacı bu andan yeniden başlar.
    case opened(at: Date)
}

/// Uzun süre boşta kalan oturumları ofiste/panelde yer kaplamasın diye küçültme kuralı. Saf mantık: zaman ve durum girer, karar çıkar.
///
/// Karar: `idleAfter` = 30 dk. Kısa tutulursa kısa molada oda kapanıp açılır (yürüyerek çıkış/giriş göz yorar); uzun tutulursa
/// 3-4 gün boş kalan oturumlar yer kaplar. 30 dk, "kahve molası"nı küçültmeden "gün sonu unutulan oturumu" toplar.
enum SessionDormancy {
    static let idleAfter: TimeInterval = 30 * 60

    /// Çalışan (düşünüyor/araç/izin bekliyor) ya da çalışan alt ajanı olan oturum asla küçülmez.
    static func isBusy(_ s: AgentSession) -> Bool { s.workingCount > 0 || s.shells.total > 0 }

    /// Otomatik küçülmenin başlayacağı an: yalnızca boşta/bitti oturumlar için (`ended` listede zaten kısa kalır). Meşgulse nil.
    static func dormantDate(_ s: AgentSession, override: SessionDockOverride?) -> Date? {
        guard !isBusy(s), s.status == .idle || s.status == .done else { return nil }
        var last = s.lastEventAt
        if case .opened(let at)? = override { last = max(last, at) }
        return last.addingTimeInterval(idleAfter)
    }

    /// Oturum şu an küçük (sekme) olarak mı gösterilmeli?
    static func isMinimized(_ s: AgentSession, override: SessionDockOverride?, now: Date) -> Bool {
        guard s.status != .ended else { return false }
        if isBusy(s) { return false } // çalışmaya başlayan oturum kendiliğinden açılır
        switch override {
        case .minimized?: return true
        case .opened?, nil:
            guard let due = dormantDate(s, override: override) else { return false }
            return now >= due
        }
    }

    /// Küçük oturumlar ve açık oturumlar (sıra korunur). `overrides` anahtarı oturum kimliğidir.
    static func partition(_ sessions: [AgentSession], overrides: [String: SessionDockOverride], now: Date)
        -> (open: [AgentSession], minimized: [AgentSession]) {
        var open: [AgentSession] = [], minimized: [AgentSession] = []
        for s in sessions {
            if isMinimized(s, override: overrides[s.id], now: now) { minimized.append(s) } else { open.append(s) }
        }
        return (open, minimized)
    }

    /// Bir sonraki otomatik küçülme anı (zamanlayıcı için); yoksa nil. Elle küçültülmüşler dahil değildir.
    static func nextDormantDate(_ sessions: [AgentSession], overrides: [String: SessionDockOverride], now: Date) -> Date? {
        sessions.compactMap { s -> Date? in
            if case .minimized? = overrides[s.id] { return nil }
            guard let due = dormantDate(s, override: overrides[s.id]), due > now else { return nil }
            return due
        }.min()
    }

    /// "3 sa", "2 g" gibi kısa boşta süresi (sekmede gösterilir).
    static func idleText(since last: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(last)))
        if s < 3600 { return "\(max(1, s / 60)) dk" }
        if s < 86_400 { return "\(s / 3600) sa" }
        return "\(s / 86_400) g"
    }
}
