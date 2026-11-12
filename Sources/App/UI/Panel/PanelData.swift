import Foundation

/// Panelin bir anlık görüntüsü. Görünümler `AppModel` yerine bunu okur; böylece testte sahte veriyle de çizilebilir.
struct PanelData: Equatable {
    var snapshot: SystemSnapshot?
    var cpuHistory: [Double] = []
    var gpuHistory: [Double] = []
    var memHistory: [Double] = []
    var downHistory: [Double] = []
    var upHistory: [Double] = []
    /// CPU ortalama sıcaklık geçmişi (°C); `TemperatureHistory` zaten menü çubuğu adımında doldurur.
    var temperatureHistory: [Double] = []
    /// Zaman damgalı son ~60 sn (SystemHistoryBuffer): metrik panellerinin grafikleri ve imleç okuması.
    var samples: [SystemSample] = []
    /// Kaynak başına sıcaklık geçmişi (°C).
    var temperatureSeries: [TemperatureSource: [Double]] = [:]

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
    /// Fatura dönemi bütçesi ve dolma tahmini; nil ise yalnız `dailyCapBytes` kullanılır.
    var budget: BudgetSnapshot?

    var blockedApps: [String] = []
    /// Yalnızca Wi-Fi/kablolu ağda (ya da her yerde) engellenenler (`prefs.blockedOnWiFi`).
    var blockedOnWiFi: [String] = []
    var isMobile = false
    var medium: PathMonitor.Medium = .wifi
    var interfaceName = ""

    var filterConnected = false
    /// Filtre 60 sn'den uzun süredir bağlı değilse uyarı ağırlığı (ayrık değer: sayfalar her adımda yeniden çizilmez).
    var filterAlert: FilterAlertLevel = .none
    var installerState: ExtensionInstaller.State = .active
    var proxyPorts: [Int] = []
    var proxyOwnerPaths: [String] = []
    var toast: AppModel.Toast?

    /// Dişli çark Dock modunda ana pencereyi (true), değilse Ayarlar penceresini açar; yalnızca ipucu metnini belirler.
    var opensMainWindow = false

    var battery: BatteryReading?
    var batteryApps: [BatteryEnergyApp] = []
    /// Görünür cihaz pilleri (en düşük üstte).
    var devices: [DeviceBattery] = []
    /// Menü çubuğundaki bellek bileşeninin (eşik modunda) seviye renkleri; panel bellek baskısını bunlarla boyar.
    var memoryLevelColors = ThresholdColors()

    /// Uygulama bazlı ölçüm yoksa listeler yerine kurulum çağrısı gösterilir.
    var showsFilterCallout: Bool { installerState != .active && !filterConnected }

    func isBlocked(_ app: String) -> Bool { blockedApps.contains(app) }

    /// Elle engellenen tüm uygulamalar kapsamlarıyla (Mobilde / Wi-Fi'de / Her yerde).
    var blockedEntries: [BlockedAppEntry] { BlockedAppEntry.list(mobile: blockedApps, wifi: blockedOnWiFi) }
}

extension PanelData {
    /// `live == false`: anlık metrik/geçmiş alanları okunmaz (boş kalır). Ağ/Mobil sayfaları bunları göstermez; böylece
    /// gövdeleri her ölçüm adımında değil, yalnızca gösterdikleri veri değişince yeniden çalışır (gözlem daralır).
    @MainActor
    init(model: AppModel, live: Bool = true) {
        let temperatures = live ? TemperatureHistory.shared.record(model.snapshot) : [:]
        self.init(
            snapshot: live ? model.snapshot : nil,
            cpuHistory: live ? model.cpuHistory : [],
            gpuHistory: live ? model.gpuHistory : [],
            memHistory: live ? model.memHistory : [],
            downHistory: live ? model.downHistory : [],
            upHistory: live ? model.upHistory : [],
            temperatureHistory: temperatures[.cpu] ?? [],
            samples: live ? model.systemHistory.samples(window: 60) : [],
            temperatureSeries: temperatures,
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
            budget: model.budget(),
            blockedApps: model.prefs.blockedOnMobile,
            blockedOnWiFi: model.prefs.blockedOnWiFi,
            isMobile: model.isMobile,
            medium: model.path.medium,
            interfaceName: model.path.interfaceName,
            filterConnected: model.filterConnected,
            filterAlert: model.filterAlert,
            installerState: model.installer.state,
            proxyPorts: model.proxy.ports,
            proxyOwnerPaths: model.proxy.ownerPaths,
            toast: model.toast,
            opensMainWindow: model.prefs.showInDock,
            battery: model.battery.reading,
            batteryApps: model.battery.energyApps,
            devices: model.devices.visibleDevices,
            memoryLevelColors: ThresholdColors.memory(in: model.prefs.menuBar.config)
        )
    }
}
