import SwiftUI

/// Önizleme maketini sığan en büyük büyütmeyle (2× → 1,5× → 1×) gösterir; "Gerçek boyut" açıkken hep 1×.
struct AdaptiveMenuBarMock: View {
    let config: MenuBarConfig
    let values: WidgetValues
    let dark: Bool
    var actualSize = false

    var body: some View {
        if actualSize {
            MenuBarMockPreview(config: config, values: values, dark: dark, zoom: 1)
        } else {
            ViewThatFits(in: .horizontal) {
                MenuBarMockPreview(config: config, values: values, dark: dark, zoom: 2)
                MenuBarMockPreview(config: config, values: values, dark: dark, zoom: 1.5)
                MenuBarMockPreview(config: config, values: values, dark: dark, zoom: 1)
            }
        }
    }
}
