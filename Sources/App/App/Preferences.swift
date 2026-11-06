import Foundation
import Observation
import ServiceManagement

/// Kullanıcı ayarları (UserDefaults destekli).
@MainActor @Observable
final class Preferences {
    private let d: UserDefaults

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

    /// Faturalama dönemi başlangıç günü (1–28). Aylık kota bu günde sıfırlanır.
    var billingCycleStartDay: Int {
        didSet {
            let c = min(28, max(1, billingCycleStartDay))
            if c != billingCycleStartDay { billingCycleStartDay = c }
            d.set(c, forKey: "billingCycleStartDay")
        }
    }
    /// Aylık (dönemlik) mobil kota (GB). `nil` = yalnızca günlük limit.
    var monthlyCapGB: Double? {
        didSet {
            if let v = monthlyCapGB, v > 0 { d.set(v, forKey: "monthlyCapGB") } else { d.removeObject(forKey: "monthlyCapGB") }
        }
    }
    /// Kademeli limit (uyar → yavaşlat → kes).
    var tierLadder: TierLadderConfig { didSet { Self.store(tierLadder, "tierLadder", d) } }
    /// Veri Tasarrufu modu (Faz A: yalnızca model + saklama).
    var dataSaver: DataSaverConfig { didSet { Self.store(dataSaver, "dataSaver", d) } }
    /// Uygulama başına kullanım kuralları.
    var usageRules: [UsageRule] { didSet { Self.store(usageRules, "usageRules", d) } }

    /// Menü çubuğu widget düzeni (eski show*Item bayrakları yalnızca ilk açılışta buraya taşınır).
    let menuBar: MenuBarConfigStore
    let panel: PanelConfigStore

    var dailyCapBytes: UInt64 { UInt64(max(0.1, dailyCapGB) * 1_000_000_000) }
    /// Aylık kota (byte); ayarlı değilse `nil`.
    var monthlyCapBytes: UInt64? { monthlyCapGB.flatMap { $0 > 0 ? UInt64($0 * 1_000_000_000) : nil } }
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

    init(defaults: UserDefaults = .standard) {
        d = defaults
        d.register(defaults: [
            "dailyCapGB": 3.0, "burstThresholdMB": 50.0, "forceMobile": false, "updateInterval": 2, "billingCycleStartDay": 1,
        ])
        dailyCapGB = d.double(forKey: "dailyCapGB")
        burstThresholdMB = d.double(forKey: "burstThresholdMB")
        forceMobile = d.bool(forKey: "forceMobile")
        showInDock = d.bool(forKey: "showInDock")
        updateInterval = d.integer(forKey: "updateInterval")
        blockedOnMobile = d.stringArray(forKey: "blockedOnMobile") ?? []
        appLimits = d.data(forKey: "appLimits").flatMap { try? JSONDecoder().decode([String: AppLimit].self, from: $0) } ?? [:]
        billingCycleStartDay = min(28, max(1, d.integer(forKey: "billingCycleStartDay")))
        monthlyCapGB = d.object(forKey: "monthlyCapGB") == nil ? nil : d.double(forKey: "monthlyCapGB")
        tierLadder = Self.load(TierLadderConfig.self, "tierLadder", d) ?? TierLadderConfig()
        dataSaver = Self.load(DataSaverConfig.self, "dataSaver", d) ?? DataSaverConfig()
        usageRules = Self.load([UsageRule].self, "usageRules", d) ?? []
        menuBar = MenuBarConfigStore(defaults: d)
        panel = PanelConfigStore(defaults: d)
    }

    func toggleBlocked(_ app: String) {
        if let i = blockedOnMobile.firstIndex(of: app) { blockedOnMobile.remove(at: i) } else { blockedOnMobile.append(app) }
    }

    private static func store<T: Encodable>(_ value: T, _ key: String, _ d: UserDefaults) {
        d.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ d: UserDefaults) -> T? {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
