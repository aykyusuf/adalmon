import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let router: SettingsRouter
    @State private var selection: SettingsSection?

    init(model: AppModel, router: SettingsRouter) {
        self.model = model
        self.router = router
        _selection = State(initialValue: router.selectedSettingsSection)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label {
                        Text(section.title)
                    } icon: {
                        SettingsSidebarIcon(symbol: section.symbol, tint: section.tint)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            let section = selection ?? router.selectedSettingsSection
            SettingsDetailView(section: section, model: model)
                .navigationTitle(section.title)
        }
        .frame(minWidth: 760, minHeight: 560)
        .onChange(of: selection) {
            if let selection { router.selectedSettingsSection = selection }
        }
        .onChange(of: router.selectedSettingsSection) {
            selection = router.selectedSettingsSection
        }
    }
}
