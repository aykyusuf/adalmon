import SwiftUI

/// Ana pencerenin canlı kökü. Kabuk model okumaz; seçili sayfa UserDefaults'ta saklanır (ham NSWindow: SceneStorage yok).
struct MainWindowRoot: View {
    let model: AppModel
    let router: SettingsRouter

    static let sectionDefaultsKey = "mainWindow.selectedSection"

    init(model: AppModel, router: SettingsRouter) {
        self.model = model
        self.router = router
        Self.restoreSection(into: router)
    }

    var body: some View {
        MainWindowView(
            model: model,
            source: .live(model),
            actions: {
                var actions = PanelActions(model: model, openApp: { [router] in router.open() }, openSettings: { [router] in router.open() })
                actions.openFilterSettings = { [router] in router.open(.filter) }
                return actions
            }(),
            router: router
        ) { section in
            SettingsDetailView(section: section, model: model)
        }
        .onAppear { Self.save(router.selectedMainSection) }
        .onChange(of: router.selectedMainSection) { Self.save(router.selectedMainSection) }
    }

    /// Yalnızca uygulama açıldıktan sonraki ilk pencerede: kayıtlı sayfa geri yüklenir
    /// (başka bir yerden, örn. dişli çarktan belirlenmiş bir seçim ezilmez).
    private static func restoreSection(into router: SettingsRouter) {
        guard !router.didRestoreMainSection else { return }
        router.didRestoreMainSection = true
        guard router.selectedMainSection == .overview,
              let id = UserDefaults.standard.string(forKey: sectionDefaultsKey),
              let saved = MainSection(id: id) else { return }
        router.selectedMainSection = saved.dockCanonical
    }

    private static func save(_ section: MainSection) {
        UserDefaults.standard.set(section.id, forKey: sectionDefaultsKey)
    }
}
