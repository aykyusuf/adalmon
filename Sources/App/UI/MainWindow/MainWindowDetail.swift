import SwiftUI

/// Seçili sayfayı kurar. Sayfalar kendi verilerini kendi gövdelerinde okur.
struct MainWindowDetail<SettingsContent: View>: View {
    let section: MainSection
    let model: AppModel
    let source: MainWindowDataSource
    let actions: PanelActions
    let router: SettingsRouter
    let settingsContent: (SettingsSection) -> SettingsContent

    var body: some View {
        switch section.dockCanonical {
        case .overview: OverviewPage(model: model, source: source, router: router)
        case .network: NetworkPageHost(model: model, source: source, actions: actions, router: router)
        case .history: HistoryPage(store: model.store)
        case .mobile: MobilePageHost(model: model, source: source, actions: actions)
        case .rules: RulesPage(model: model)
        case .processes: ProcessesPage(model: model, router: router)
        case .battery: BatteryPage(monitor: model.battery, store: model.store, router: router, devices: model.devices, prefs: model.prefs)
        case .wallpaper: WallpaperPage(service: .shared, agentsEnabled: model.prefs.agentsEnabled) { router.open(.agents) }
        case .agentOffice: AgentOfficePage(model: model, router: router)
        case .cleanup: CleanupPage(router: router)
        case .settings(let settings): SettingsPage(section: settings) { settingsContent(settings) }
        }
    }
}
