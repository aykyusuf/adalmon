import Foundation

/// Panelin bir anlık görüntüsü. Görünümler `AppModel` yerine bunu okur; böylece testte sahte veriyle de çizilebilir.
struct PanelData {
    var snapshot: SystemSnapshot?
    var cpuHistory: [Double] = []
    var gpuHistory: [Double] = []
    var memHistory: [Double] = []
    var downHistory: [Double] = []
    var upHistory: [Double] = []

    var last60: [AppUsage] = []
    var today: [AppUsage] = []
    var downLast60: UInt64 = 0
    var upLast60: UInt64 = 0
    var downToday: UInt64 = 0
    var upToday: UInt64 = 0

    var mobileToday: UInt64 = 0
    var wifiToday: UInt64 = 0
    var unattributedMobile: UInt64 = 0
    var dailyCapBytes: UInt64 = 3_000_000_000

    var blockedApps: [String] = []
    var isMobile = false
    var medium: PathMonitor.Medium = .wifi
    var interfaceName = ""

    var filterConnected = false
    var installerState: ExtensionInstaller.State = .active
    var proxyPorts: [Int] = []
    var proxyOwnerPaths: [String] = []
    var toast: AppModel.Toast?

    /// Uygulama bazlı ölçüm yoksa listeler yerine kurulum çağrısı gösterilir.
    var showsFilterCallout: Bool { installerState != .active && !filterConnected }

    func isBlocked(_ app: String) -> Bool { blockedApps.contains(app) }
}

extension PanelData {
    @MainActor
    init(model: AppModel) {
        self.init(
            snapshot: model.snapshot,
            cpuHistory: model.cpuHistory,
            gpuHistory: model.gpuHistory,
            memHistory: model.memHistory,
            downHistory: model.downHistory,
            upHistory: model.upHistory,
            last60: model.usage.last60,
            today: model.usage.today,
            downLast60: model.downLast60,
            upLast60: model.upLast60,
            downToday: model.downToday,
            upToday: model.upToday,
            mobileToday: model.mobileToday,
            wifiToday: model.wifiToday,
            unattributedMobile: model.unattributedMobile,
            dailyCapBytes: model.prefs.dailyCapBytes,
            blockedApps: model.prefs.blockedOnMobile,
            isMobile: model.isMobile,
            medium: model.path.medium,
            interfaceName: model.path.interfaceName,
            filterConnected: model.filterConnected,
            installerState: model.installer.state,
            proxyPorts: model.proxy.ports,
            proxyOwnerPaths: model.proxy.ownerPaths,
            toast: model.toast
        )
    }
}
