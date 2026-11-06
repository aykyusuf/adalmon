import SwiftUI

/// "Ağ kullanımı" sayfası için canlı veriyi yalnızca bu sayfa görünürken okur.
struct NetworkPageHost: View {
    let model: AppModel
    let source: MainWindowDataSource
    let actions: PanelActions
    let router: SettingsRouter

    var body: some View {
        // Canlı metrik okunmaz + sayfa yalnızca gösterdiği veri değişince yeniden çizilir (`==`).
        NetworkUsagePage(data: source.pageData(), limits: source.limits(), actions: actions, model: model, router: router)
            .equatable()
    }
}
