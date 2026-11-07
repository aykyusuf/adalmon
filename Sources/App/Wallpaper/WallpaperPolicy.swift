import Foundation

/// Duraklatma kuralları: her biri ayrı bir anahtar, hepsi varsayılan AÇIK. Kullanıcı hangisini isterse kapatır
/// ("kesin dur olmasın, devam et" diyebilsin).
struct WallpaperPauseRules: Codable, Equatable, Sendable {
    /// Pildeyken dur.
    var pauseOnBattery = true
    /// Düşük Güç Modunda dur.
    var pauseOnLowPower = true
    /// Masaüstü görünmüyorken dur: pencereler örtüyor, tam ekran uygulama, ekran kilitli / ekran koruyucu, ekran uykuda.
    var pauseWhenDesktopHidden = true
}

/// Politikanın girdileri (saf veri). Ekran başına `desktopVisible` ve `fullScreen` değişir, diğerleri sistem geneli.
struct WallpaperPolicyInput: Equatable, Sendable {
    var onBattery = false
    var lowPower = false
    /// Masaüstünün gözle görünür kısmı var mı (başka pencereler ekranın büyük kısmını örtmüyor)?
    var desktopVisible = true
    /// Oturum kilitli ya da ekran koruyucu çalışıyor / hızlı kullanıcı değişimi.
    var locked = false
    var displayAsleep = false
    /// Bu ekranda tam ekran bir uygulama var.
    var fullScreen = false
}

/// Kullanıcının elle verdiği karar: kurallardan bağımsız.
enum WallpaperUserOverride: String, Codable, Equatable, Sendable, CaseIterable {
    /// Kurallar karar verir.
    case auto
    /// Kullanıcı duraklattı: hiçbir koşulda oynamaz.
    case forcePause
    /// "Yine de oynat": pil ve Düşük Güç kurallarını yok sayar. Fiziksel olarak izlenemeyen durumlar
    /// (kilit, ekran uykusu) yine de durdurur: kimsenin görmediği kareyi çözmenin anlamı yok.
    case forcePlay
}

enum WallpaperPauseReason: String, Codable, Equatable, Sendable {
    case user, battery, lowPower, locked, displayAsleep, fullScreen, covered

    /// Durum satırı: "Duraklatıldı: pilde".
    var statusText: String {
        switch self {
        case .user: "Duraklatıldı: elle"
        case .battery: "Duraklatıldı: pilde"
        case .lowPower: "Duraklatıldı: Düşük Güç Modu"
        case .locked: "Duraklatıldı: ekran kilitli"
        case .displayAsleep: "Duraklatıldı: ekran uykuda"
        case .fullScreen: "Duraklatıldı: tam ekran uygulama"
        case .covered: "Duraklatıldı: masaüstü örtülü"
        }
    }
}

enum WallpaperDecision: Equatable, Sendable {
    case play
    case pause(WallpaperPauseReason)

    var isPlaying: Bool { self == .play }
}

/// Oynat / duraklat kararı: saf fonksiyon (birim testli). Öncelik: elle duraklatma > fiziksel durumlar > pil > Düşük Güç.
enum WallpaperPolicy {
    static func decide(_ input: WallpaperPolicyInput, rules: WallpaperPauseRules, override: WallpaperUserOverride = .auto) -> WallpaperDecision {
        if override == .forcePause { return .pause(.user) }
        if rules.pauseWhenDesktopHidden {
            if input.displayAsleep { return .pause(.displayAsleep) }
            if input.locked { return .pause(.locked) }
        }
        if override != .forcePlay {
            if rules.pauseOnBattery && input.onBattery { return .pause(.battery) }
            if rules.pauseOnLowPower && input.lowPower { return .pause(.lowPower) }
        }
        if rules.pauseWhenDesktopHidden {
            if input.fullScreen { return .pause(.fullScreen) }
            if !input.desktopVisible { return .pause(.covered) }
        }
        return .play
    }
}
