import SwiftUI

/// "Mobil veri" sayfası için canlı veriyi yalnızca bu sayfa görünürken okur.
struct MobilePageHost: View {
    let model: AppModel
    let source: MainWindowDataSource
    let actions: PanelActions

    var body: some View {
        // Canlı metrik okunmaz + sayfa yalnızca gösterdiği veri değişince yeniden çizilir (`==`).
        MobileDataPage(data: source.pageData(), actions: actions, model: model)
            .equatable()
    }
}
