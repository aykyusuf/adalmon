import SwiftUI

/// Bir Ayarlar bölümünün içeriği. Hem ayrı Ayarlar penceresinde hem de ana pencerede kullanılır.
struct SettingsDetailView: View {
    let section: SettingsSection
    let model: AppModel

    var body: some View {
        switch section {
        case .menuBar: MenuBarCardsTab(model: model)
        case .panel: PanelSettingsPane(model: model)
        case .batteryAlerts: BatteryAlertsSettingsPane(model: model)
        case .throttle: ThrottleSettingsPane(model: model)
        case .mobileData: MobileDataSettingsTab(model: model)
        case .filter: FilterSettingsTab(model: model)
        case .general: GeneralSettingsTab(prefs: model.prefs)
        }
    }
}
