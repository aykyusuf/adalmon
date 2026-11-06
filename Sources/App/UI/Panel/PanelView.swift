import SwiftUI

/// Canlı panel: `AppModel`'den anlık veri üretir ve `PanelContent`'i çizer. Yalnızca panel açıkken var olur.
struct PanelView: View {
    let model: AppModel
    let openApp: @MainActor () -> Void
    let openSettings: @MainActor () -> Void
    var onSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        @Bindable var store = model.prefs.panel
        PanelContent(data: PanelData(model: model),
                     config: $store.config,
                     actions: PanelActions(model: model, openApp: openApp, openSettings: openSettings))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
    }
}
