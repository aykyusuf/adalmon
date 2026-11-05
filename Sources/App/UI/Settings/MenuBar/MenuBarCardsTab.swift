import SwiftUI

/// Default "Menü çubuğu" page: a read-only live preview, global options and one simple card per metric.
/// Card order is menu bar order. The advanced component editor opens as a sheet.
struct MenuBarCardsTab: View {
    let model: AppModel
    @Bindable var store: MenuBarConfigStore
    @State private var values = WidgetValues.sample
    @State private var cards = MetricCardConfig.defaults
    @State private var isSimple = true
    @State private var showsAdvancedEditor = false

    init(model: AppModel) {
        self.model = model
        self.store = model.prefs.menuBar
    }

    var body: some View {
        MenuBarCardsForm(store: store, values: values, cards: $cards, isSimple: isSimple,
                         onOpenAdvanced: { showsAdvancedEditor = true })
            .liveWidgetValues($values, model: model)
            .onAppear(perform: syncFromStore)
            .onChange(of: store.config.components) { syncFromStore() }
            .onChange(of: cards) {
                guard isSimple else { return }
                store.apply(cards: cards)
            }
            .sheet(isPresented: $showsAdvancedEditor) {
                AdvancedMenuBarEditorSheet(model: model)
            }
    }

    private func syncFromStore() {
        let parsed = store.cards
        isSimple = parsed != nil
        if let parsed, parsed != cards { cards = parsed }
    }
}
