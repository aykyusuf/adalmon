import Foundation

/// Gerçek uygulama durumuna bağlı arka uç: mevcut model eylemlerini yeniden kullanır (toast, bağlantı yenileme dahil).
@MainActor
final class LiveIntentBackend: AdalmonIntentBackend {
    private let model: AppModel
    private let openRoute: @MainActor (AdalmonRoute) -> Void

    init(model: AppModel, openRoute: @escaping @MainActor (AdalmonRoute) -> Void) {
        self.model = model
        self.openRoute = openRoute
    }

    func batteryStatus() -> BatteryStatusAnswer? {
        guard let r = model.battery.reading else { return nil }
        return BatteryStatusAnswer(level: r.level, state: WidgetSnapshotBuilder.state(r.state), minutesToEmpty: r.timeToEmptyMinutes,
                                   minutesToFull: r.timeToFullMinutes, healthPercent: r.primaryHealthPercent)
    }

    func deviceBatteries() -> [DeviceBatteryAnswer] {
        model.devices.devices
            .filter { model.prefs.deviceSettings[$0.id]?.hidden != true }
            .map { DeviceBatteryAnswer(name: $0.name, level: $0.summaryLevel, isCharging: $0.isCharging, isConnected: $0.isConnected) }
    }

    func mobileUsage() -> MobileUsageAnswer {
        let monthly = model.prefs.monthlyCapBytes
        return MobileUsageAnswer(todayBytes: model.mobileToday, dailyCapBytes: model.prefs.dailyCapBytes,
                                 cycleUsedBytes: monthly == nil ? nil : model.budget().cycleUsedBytes, monthlyCapBytes: monthly,
                                 isOnMobile: model.isMobile)
    }

    func open(route: AdalmonRoute) { openRoute(route) }
    func setThrottle(appID: String, limit: AppLimit) { model.setLimit(appID, limit) }
    func removeThrottle(appID: String) { model.setLimit(appID, nil) }
    func setBlockedOnMobile(appID: String, blocked: Bool) { model.setBlocked(appID, blocked) }

    func knownApps() -> [IntentAppInfo] {
        var seen = Set<String>()
        var result: [IntentAppInfo] = []
        let candidates = model.usage.today.map(\.app) + model.prefs.appLimits.keys + model.prefs.blockedOnMobile
        for app in candidates where seen.insert(app).inserted {
            result.append(IntentAppInfo(id: app, name: AppCatalog.shared.name(for: app)))
        }
        return result
    }

    func appName(for id: String) -> String { AppCatalog.shared.name(for: id) }
}
