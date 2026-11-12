import Foundation

/// Uygulama seçicinin listesi: bugün veri kullananlar, son 60 sn, mevcut sınır/engel/kural kayıtları.
enum KnownApps {
    @MainActor
    static func collect(model: AppModel, extra: [String] = []) -> [String] {
        var keys = Set<String>(extra)
        for usage in model.usage.today { keys.insert(usage.app) }
        for usage in model.usage.last60 { keys.insert(usage.app) }
        keys.formUnion(model.prefs.appLimits.keys)
        keys.formUnion(model.prefs.blockedOnMobile)
        keys.formUnion(model.prefs.blockedOnWiFi)
        keys.formUnion(model.prefs.usageRules.map(\.app))
        keys.formUnion(model.prefs.tierLadder.protectedApps)
        keys.formUnion(model.prefs.dataSaver.allowlist)
        keys.remove("")
        return keys.sorted { AppCatalog.shared.name(for: $0).localizedCaseInsensitiveCompare(AppCatalog.shared.name(for: $1)) == .orderedAscending }
    }
}
