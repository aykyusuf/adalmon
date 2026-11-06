import SwiftUI

/// Ana pencerenin canlı kökü: `AppModel`'i okuyup saf `MainWindowView`'e anlık görüntü olarak verir.
struct MainWindowRoot: View {
    let model: AppModel
    let router: SettingsRouter

    var body: some View {
        MainWindowView(
            data: PanelData(model: model),
            limits: model.prefs.appLimits,
            actions: PanelActions(model: model, openSettings: { [router] in router.open() }),
            router: router
        ) { section in
            SettingsDetailView(section: section, model: model)
        }
    }
}
