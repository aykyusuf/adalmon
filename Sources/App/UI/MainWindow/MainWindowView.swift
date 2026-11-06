import SwiftUI

struct MainWindowView<SettingsContent: View>: View {
    let data: PanelData
    let limits: [String: AppLimit]
    let actions: PanelActions
    let router: SettingsRouter
    let settingsContent: (SettingsSection) -> SettingsContent
    @State private var selection: MainSection?

    init(data: PanelData, limits: [String: AppLimit], actions: PanelActions, router: SettingsRouter,
         @ViewBuilder settingsContent: @escaping (SettingsSection) -> SettingsContent) {
        self.data = data
        self.limits = limits
        self.actions = actions
        self.router = router
        self.settingsContent = settingsContent
        _selection = State(initialValue: router.selectedMainSection)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(MainSection.pages) { row($0) }
                Section("Ayarlar") {
                    ForEach(SettingsSection.allCases) { row(.settings($0)) }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail(for: selection ?? router.selectedMainSection)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: selection) {
            if let selection { router.selectedMainSection = selection }
        }
        .onChange(of: router.selectedMainSection) {
            selection = router.selectedMainSection
        }
    }

    private func row(_ section: MainSection) -> some View {
        NavigationLink(value: section) {
            Label {
                Text(section.title)
            } icon: {
                SettingsSidebarIcon(symbol: section.symbol, tint: section.tint)
            }
        }
    }

    @ViewBuilder
    private func detail(for section: MainSection) -> some View {
        switch section {
        case .overview: OverviewPage(data: data)
        case .network: NetworkUsagePage(data: data, limits: limits, actions: actions)
        case .mobile: MobileDataPage(data: data)
        case .settings(let settings): SettingsPage(section: settings) { settingsContent(settings) }
        }
    }
}
