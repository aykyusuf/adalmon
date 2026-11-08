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
    /// Çekirdek bellek basıncı KRİTİK iken dur (uyarı seviyesinde oynamaya devam eder).
    var pauseOnMemoryCritical = true
    /// Isıl durum "serious" ya da üstündeyken dur ("fair"de devam eder).
    var pauseOnThermal = true
    /// Sistem CPU'su 30 sn ortalama %85'in üstündeyken dur, %60'ın altına inince devam et.
    var pauseOnHighCPU = true
}

extension WallpaperPauseRules {
    /// Eski kayıtlarda olmayan kurallar varsayılana (AÇIK) düşer: yeni kural eklemek kayıtlı ayarları silmez.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WallpaperPauseRules()
        pauseOnBattery = try c.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? d.pauseOnBattery
        pauseOnLowPower = try c.decodeIfPresent(Bool.self, forKey: .pauseOnLowPower) ?? d.pauseOnLowPower
        pauseWhenDesktopHidden = try c.decodeIfPresent(Bool.self, forKey: .pauseWhenDesktopHidden) ?? d.pauseWhenDesktopHidden
        pauseOnMemoryCritical = try c.decodeIfPresent(Bool.self, forKey: .pauseOnMemoryCritical) ?? d.pauseOnMemoryCritical
        pauseOnThermal = try c.decodeIfPresent(Bool.self, forKey: .pauseOnThermal) ?? d.pauseOnThermal
        pauseOnHighCPU = try c.decodeIfPresent(Bool.self, forKey: .pauseOnHighCPU) ?? d.pauseOnHighCPU
    }
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
    /// Çekirdek bellek basıncı kritik (kern.memorystatus_vm_pressure_level == 4).
    var memoryCritical = false
    /// ProcessInfo.thermalState >= .serious.
    var thermalSerious = false
    /// CPU yük kapısı "dur" diyor (bkz. `CPULoadGate`: 30 sn ortalama > %85, %60 altına inene kadar).
    var cpuBusy = false
}

/// Kullanıcının elle verdiği karar: kurallardan bağımsız.
enum WallpaperUserOverride: String, Codable, Equatable, Sendable, CaseIterable {
    /// Kurallar karar verir.
    case auto
    /// Kullanıcı duraklattı: hiçbir koşulda oynamaz.
    case forcePause
    /// "Yine de oynat": pil, Düşük Güç, bellek, ısı ve CPU kurallarını yok sayar. Fiziksel olarak izlenemeyen durumlar
    /// (kilit, ekran uykusu) yine de durdurur: kimsenin görmediği kareyi çözmenin anlamı yok.
    case forcePlay
}

enum WallpaperPauseReason: String, Codable, Equatable, Sendable {
    case user, battery, lowPower, locked, displayAsleep, fullScreen, covered, memoryCritical, thermal, highCPU

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
        case .memoryCritical: "Duraklatıldı: bellek baskısı kritik"
        case .thermal: "Duraklatıldı: Mac ısındı"
        case .highCPU: "Duraklatıldı: CPU çok yoğun"
        }
    }
}

enum WallpaperDecision: Equatable, Sendable {
    case play
    case pause(WallpaperPauseReason)

    var isPlaying: Bool { self == .play }
}

/// Oynat / duraklat kararı: saf fonksiyon (birim testli).
/// Öncelik: elle duraklatma > fiziksel durumlar (uyku, kilit) > pil > Düşük Güç > bellek kritik > ısı > CPU > tam ekran > örtülü.
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
            if rules.pauseOnMemoryCritical && input.memoryCritical { return .pause(.memoryCritical) }
            if rules.pauseOnThermal && input.thermalSerious { return .pause(.thermal) }
            if rules.pauseOnHighCPU && input.cpuBusy { return .pause(.highCPU) }
        }
        if rules.pauseWhenDesktopHidden {
            if input.fullScreen { return .pause(.fullScreen) }
            if !input.desktopVisible { return .pause(.covered) }
        }
        return .play
    }

    /// sysctl kern.memorystatus_vm_pressure_level: 1 = normal, 2 = uyarı, 4 = kritik. Yalnızca kritik durdurur.
    static func isMemoryCritical(sysctlLevel: Int32?) -> Bool { sysctlLevel == 4 }

    /// Yalnızca serious / critical durdurur; nominal ve fair'de oynamaya devam.
    static func isThermalSerious(_ state: ProcessInfo.ThermalState) -> Bool { state.rawValue >= ProcessInfo.ThermalState.serious.rawValue }
}

/// "CPU çok yoğunken dur" kapısı: saf, zaman damgalı örneklerle çalışır (zamanlayıcı yok; örnekler mevcut metrik
/// örnekleyicisinden gelir). Duraklatma: son `window` sn'nin ortalaması `pauseAbove` üstünde VE örnekler en az `window` sn'yi
/// kesintisiz kapsıyor. Devam: aynı pencere ortalaması `resumeBelow` altına inince (histerezis). Kısa sıçrama ortalamayı aşmaz.
struct CPULoadGate: Equatable, Sendable {
    var window: TimeInterval = 30
    /// Kesir (0…1): `CPUStats.total` ile aynı birim.
    var pauseAbove = 0.85
    var resumeBelow = 0.60
    /// Ardışık iki örnek arası bundan uzunsa (uyku, duraklatılmış örnekleme) geçmiş sıfırlanır.
    var maxGap: TimeInterval = 15

    private(set) var samples: [Sample] = []
    /// Kesintisiz örnek dizisinin başladığı an.
    private(set) var runStart: Date?
    private(set) var shouldPause = false

    struct Sample: Equatable, Sendable {
        var time: Date
        var load: Double
    }

    var average: Double? { samples.isEmpty ? nil : samples.map(\.load).reduce(0, +) / Double(samples.count) }

    /// Yeni örnek ekler, kararı döndürür.
    @discardableResult
    mutating func ingest(_ load: Double, at time: Date) -> Bool {
        let value = load.isFinite ? min(1, max(0, load)) : 0
        if let last = samples.last, time.timeIntervalSince(last.time) > maxGap || time < last.time {
            samples.removeAll()
            runStart = nil
        }
        if runStart == nil { runStart = time }
        samples.append(Sample(time: time, load: value))
        let cutoff = time.addingTimeInterval(-window)
        samples.removeAll { $0.time < cutoff }
        guard let avg = average, let runStart else { return shouldPause }
        if shouldPause {
            if avg < resumeBelow { shouldPause = false }
        } else if time.timeIntervalSince(runStart) >= window && avg > pauseAbove {
            shouldPause = true
        }
        return shouldPause
    }

    mutating func reset() {
        samples.removeAll()
        runStart = nil
        shouldPause = false
    }
}
