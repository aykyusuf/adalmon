import Foundation

extension AdalmonRoute {
    /// Dock modunda açılacak ana pencere bölümü.
    var mainSection: MainSection {
        switch self {
        case .overview, .system: .overview
        case .network: .network
        case .history: .history
        case .mobile: .mobile
        case .rules: .rules
        case .processes: .processes
        case .battery: .battery
        case .widgets: .settings(.widgets)
        case .shortcuts: .settings(.shortcuts)
        }
    }

    /// Dock modu kapalıyken (ana pencere yok) açılacak ayar bölümü.
    var settingsFallback: SettingsSection {
        switch self {
        case .battery: .batteryAlerts
        case .mobile: .mobileData
        case .network, .rules: .filter
        case .system, .overview, .history, .processes: .panel
        case .widgets: .widgets
        case .shortcuts: .shortcuts
        }
    }
}
