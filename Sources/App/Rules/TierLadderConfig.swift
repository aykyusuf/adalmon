import Foundation

/// Kademeli limit: uyar → yavaşlat → kes. Kullanım yüzdesi mobil günlük toplamın (fiziksel arayüz sayaçları)
/// günlük limite (ve varsa aylık limite) oranıdır.
struct TierLadderConfig: Codable, Equatable, Sendable {
    var enabled = false
    var warnPercent = 80
    var slowPercent = 95
    var cutPercent = 100
    /// Yavaşlatma kademesinde korunmayan uygulamalara uygulanan indirme sınırı (byte/sn). Varsayılan 256 KB/sn.
    var slowDownBytesPerSec: Int? = 256 * 1024
    var slowUpBytesPerSec: Int?
    /// Sınırın uygulanacağı ağ. `allNetworks`'te kesme (engel) Wi-Fi'de Faz B'ye kadar uygulanamaz.
    var appliesTo: NetworkScope = .mobileOnly
    /// Yavaşlatma/kesmeden muaf uygulama anahtarları (sistem yolları, Adalmon ve proxy sahibi zaten her zaman korunur).
    var protectedApps: [String] = []
    /// Kesme kademesinde engellenecek en çok tüketen uygulama sayısı (0 = görülen tüm korunmasızlar).
    var cutTopCount = 10

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, warnPercent, slowPercent, cutPercent, slowDownBytesPerSec, slowUpBytesPerSec, appliesTo, protectedApps, cutTopCount
    }

    /// Eksik alanlar varsayılana düşer.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        warnPercent = try c.decodeIfPresent(Int.self, forKey: .warnPercent) ?? warnPercent
        slowPercent = try c.decodeIfPresent(Int.self, forKey: .slowPercent) ?? slowPercent
        cutPercent = try c.decodeIfPresent(Int.self, forKey: .cutPercent) ?? cutPercent
        slowDownBytesPerSec = try c.decodeIfPresent(Int.self, forKey: .slowDownBytesPerSec) ?? slowDownBytesPerSec
        slowUpBytesPerSec = try c.decodeIfPresent(Int.self, forKey: .slowUpBytesPerSec)
        appliesTo = try c.decodeIfPresent(NetworkScope.self, forKey: .appliesTo) ?? appliesTo
        protectedApps = try c.decodeIfPresent([String].self, forKey: .protectedApps) ?? protectedApps
        cutTopCount = try c.decodeIfPresent(Int.self, forKey: .cutTopCount) ?? cutTopCount
    }

    /// Eşikler sıralı ve pozitif olacak şekilde düzeltilmiş kopya (warn ≤ slow ≤ cut).
    var normalized: TierLadderConfig {
        var c = self
        c.warnPercent = max(1, warnPercent)
        c.slowPercent = max(c.warnPercent, slowPercent)
        c.cutPercent = max(c.slowPercent, cutPercent)
        return c
    }

    /// Yavaşlatma kademesinin `AppLimit`'i; sınır tanımsızsa `nil`.
    var slowLimit: AppLimit? {
        let l = AppLimit(downBytesPerSec: slowDownBytesPerSec, upBytesPerSec: slowUpBytesPerSec, onlyOnMobile: appliesTo == .mobileOnly)
        return l.hasCap ? l : nil
    }
}
