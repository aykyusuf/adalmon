import Foundation
import Observation
import ServiceManagement

/// Kullanıcı ayarları (UserDefaults destekli).
@MainActor @Observable
final class Preferences {
    private let d = UserDefaults.standard

    var dailyCapGB: Double { didSet { d.set(dailyCapGB, forKey: "dailyCapGB") } }
    var burstThresholdMB: Double { didSet { d.set(burstThresholdMB, forKey: "burstThresholdMB") } }
    /// Panel kapalıyken güncelleme aralığı (sn). Daha seyrek = daha az pil.
    var updateInterval: Int { didSet { d.set(updateInterval, forKey: "updateInterval") } }
    var forceMobile: Bool { didSet { d.set(forceMobile, forKey: "forceMobile") } }
    /// Dock'ta simge ve ana pencere göster (kapalıysa yalnızca menü çubuğu uygulaması).
    var showInDock: Bool { didSet { d.set(showInDock, forKey: "showInDock") } }
    var blockedOnMobile: [String] { didSet { d.set(blockedOnMobile, forKey: "blockedOnMobile") } }
    /// Uygulama anahtarı → hız sınırı (JSON olarak saklanır).
    var appLimits: [String: AppLimit] { didSet { d.set(try? JSONEncoder().encode(appLimits), forKey: "appLimits") } }

    /// Menü çubuğu widget düzeni (eski show*Item bayrakları yalnızca ilk açılışta buraya taşınır).
    let menuBar: MenuBarConfigStore
    let panel: PanelConfigStore

    var dailyCapBytes: UInt64 { UInt64(max(0.1, dailyCapGB) * 1_000_000_000) }
    var burstThresholdBytes: UInt64 { UInt64(max(1, burstThresholdMB) * 1_000_000) }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Adalmon launchAtLogin: \(error.localizedDescription)")
            }
        }
    }

    init() {
        d.register(defaults: [
            "dailyCapGB": 3.0, "burstThresholdMB": 50.0, "forceMobile": false, "updateInterval": 2,
        ])
        dailyCapGB = d.double(forKey: "dailyCapGB")
        burstThresholdMB = d.double(forKey: "burstThresholdMB")
        forceMobile = d.bool(forKey: "forceMobile")
        showInDock = d.bool(forKey: "showInDock")
        updateInterval = d.integer(forKey: "updateInterval")
        blockedOnMobile = d.stringArray(forKey: "blockedOnMobile") ?? []
        appLimits = d.data(forKey: "appLimits").flatMap { try? JSONDecoder().decode([String: AppLimit].self, from: $0) } ?? [:]
        menuBar = MenuBarConfigStore(defaults: d)
        panel = PanelConfigStore(defaults: d)
    }

    func toggleBlocked(_ app: String) {
        if let i = blockedOnMobile.firstIndex(of: app) { blockedOnMobile.remove(at: i) } else { blockedOnMobile.append(app) }
    }
}
