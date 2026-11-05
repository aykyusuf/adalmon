import SwiftUI

/// macOS 26 Sistem Ayarları tarzı pencere: Liquid Glass kenar çubuğu + gruplanmış form içerik.
struct SettingsView: View {
    let model: AppModel
    @State private var selection: SettingsSection? = .menuBar

    init(model: AppModel) {
        self.model = model
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
            detail(for: selection ?? .menuBar)
                .navigationTitle((selection ?? .menuBar).title)
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        switch section {
        case .menuBar: MenuBarCardsTab(model: model)
        case .panel: PanelSettingsPane(model: model)
        case .throttle: ThrottleSettingsPane(model: model)
        case .mobileData: MobileDataSettingsTab(model: model)
        case .filter: FilterSettingsTab(model: model)
        case .general: GeneralSettingsTab(prefs: model.prefs)
        }
    }
}
