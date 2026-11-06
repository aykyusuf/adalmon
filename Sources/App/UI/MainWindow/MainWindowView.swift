import SwiftUI

/// Ana pencerenin kabuğu: kenar çubuğu + seçili sayfa. Kabuk `AppModel`'i okumaz; canlı veriyi yalnızca sayfalar okur.
struct MainWindowView<SettingsContent: View>: View {
    let model: AppModel
    let source: MainWindowDataSource
    let actions: PanelActions
    let router: SettingsRouter
    let settingsContent: (SettingsSection) -> SettingsContent
    @State private var selection: MainSection?

    init(model: AppModel, source: MainWindowDataSource, actions: PanelActions, router: SettingsRouter,
         @ViewBuilder settingsContent: @escaping (SettingsSection) -> SettingsContent) {
        self.model = model
        self.source = source
        self.actions = actions
        self.router = router
        self.settingsContent = settingsContent
        _selection = State(initialValue: router.selectedMainSection)
    }

    var body: some View {
        NavigationSplitView {
            MainSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            MainWindowDetail(section: selection ?? router.selectedMainSection, model: model, source: source,
                             actions: actions, router: router, settingsContent: settingsContent)
        }
        .frame(minWidth: 940, minHeight: 600)
        .onChange(of: selection) {
            if let selection { router.selectedMainSection = selection }
        }
        .onChange(of: router.selectedMainSection) {
            selection = router.selectedMainSection
        }
    }
}
