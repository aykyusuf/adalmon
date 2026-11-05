import AppKit
import SwiftUI

/// Live rendering of one or more components exactly as the menu bar draws them, on a small bar-like chip.
struct ComponentPreview: View {
    let components: [MenuBarComponent]
    let config: MenuBarConfig
    let values: WidgetValues
    var zoom: CGFloat = 1.5
    var minHeight: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        // Rasterized here on the main actor so SwiftUI never runs the AppKit drawing handler elsewhere.
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        let image = MenuBarComposer.image(for: components, config: config, values: values, appearance: appearance.name, zoom: zoom)
        Image(nsImage: MenuBarComposer.bitmap(image, appearance: appearance, scale: 2))
            .padding(.horizontal, 6 * zoom)
            .frame(minHeight: max(minHeight, 26 * zoom))
            .background(dark ? Color(white: 0.11) : Color(white: 0.985), in: .rect(cornerRadius: 6 * zoom))
            .overlay(RoundedRectangle(cornerRadius: 6 * zoom).strokeBorder(.separator, lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MenuBarComposer.accessibilitySummary(for: components, values: values))
    }
}
