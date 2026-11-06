import Foundation

/// Elle ayarlar + kural çıktısı birleşimi: filtreye gidecek `limits`, `blockedOnMobile` ve `blockedAlways`.
struct EffectiveConfig: Equatable, Sendable {
    var limits: [String: AppLimit] = [:]
    var blocked: [String] = []
    /// Her ağda engellenecekler (`FilterConfig.blockedAlways`).
    var blockedAlways: Set<String> = []
}

/// Birleştirme kuralları (saf, test edilir):
/// - Engel: birleşim. Elle engeller ve sırası aynen korunur, kural engelleri sona eklenir.
/// - Hız sınırı: yön başına en kısıtlayıcı (en küçük pozitif sınır) kazanır.
/// - Kapsam farklıysa (biri yalnız-mobil, diğeri tüm ağlar) tek `onlyOnMobile` bayrağı ikisini birden ifade edemez;
///   şu anki ağa göre çözülür: mobildeyken ikisi de geçerli (en kısıtlayıcı, bayrak false), Wi-Fi'deyken yalnız
///   tüm-ağlar olanlar. Böylece yalnız-mobil bir sınır Wi-Fi'ye taşmaz, kullanıcının elle ayarı hiçbir ağda gevşemez.
enum EffectiveConfigBuilder {
    static func build(manualLimits: [String: AppLimit], manualBlocked: [String], output: RuleOutput, onMobile: Bool) -> EffectiveConfig {
        var limits = manualLimits
        for (app, contributions) in output.limits {
            var all: [AppLimit] = contributions.map(\.limit)
            if let manual = manualLimits[app] { all.insert(manual, at: 0) }
            if let merged = merge(all, onMobile: onMobile) { limits[app] = merged }
        }
        var blocked = manualBlocked
        var seen = Set(manualBlocked)
        for app in output.blocked.keys.sorted() where seen.insert(app).inserted { blocked.append(app) }
        return EffectiveConfig(limits: limits, blocked: blocked, blockedAlways: output.blockedAlways)
    }

    /// Birden çok sınırı tek `AppLimit`'e indirger. Tek giriş olduğu gibi döner (elle girişe dokunulmaz).
    static func merge(_ inputs: [AppLimit], onMobile: Bool) -> AppLimit? {
        let capped = inputs.filter(\.hasCap)
        if capped.count <= 1 { return capped.first ?? inputs.first }
        let mobileOnly = capped.filter(\.onlyOnMobile)
        let wide = capped.filter { !$0.onlyOnMobile }
        let flag: Bool
        let used: [AppLimit]
        if wide.isEmpty { flag = true; used = mobileOnly }
        else if mobileOnly.isEmpty { flag = false; used = wide }
        else { flag = false; used = onMobile ? capped : wide }
        func minRate(_ d: ThrottleDirection) -> Int? { used.compactMap { $0.rate(d) }.min() }
        return AppLimit(downBytesPerSec: minRate(.down), upBytesPerSec: minRate(.up), onlyOnMobile: flag)
    }

    /// `old` → `new` sınırı kısıtlayıcılaştırdı mı (yeni eklendi, düştü ya da "yalnız mobil" kalktı).
    static func isStricter(_ new: AppLimit, than old: AppLimit?) -> Bool {
        guard let old else { return true }
        func cap(_ v: Int?) -> Int { v.flatMap { $0 > 0 ? $0 : nil } ?? .max }
        return cap(new.downBytesPerSec) < cap(old.downBytesPerSec)
            || cap(new.upBytesPerSec) < cap(old.upBytesPerSec)
            || (old.onlyOnMobile && !new.onlyOnMobile)
    }
}
