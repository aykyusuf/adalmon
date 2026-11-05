import SwiftUI

/// Önizlemeler için canlı değerler: yalnızca görünüm ekrandayken saniyede bir yenilenir
/// (`.task` görünüm kaybolunca iptal olur; gövde modeli doğrudan izlemez).
struct LiveWidgetValues: ViewModifier {
    let model: AppModel
    @Binding var values: WidgetValues

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                values = WidgetValues(model: model)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

extension View {
    func liveWidgetValues(_ values: Binding<WidgetValues>, model: AppModel) -> some View {
        modifier(LiveWidgetValues(model: model, values: values))
    }
}
