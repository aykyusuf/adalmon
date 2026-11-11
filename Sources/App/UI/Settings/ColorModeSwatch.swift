import SwiftUI

/// Renk modunu simgeleyen yuvarlak örnek.
struct ColorModeSwatch: View {
    let mode: ColorMode
    let component: MenuBarComponent

    var body: some View {
        Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
            .frame(width: 16, height: 16)
    }

    private var thresholdColors: [Color] {
        guard !component.levelColors.isDefault else { return [.green, .orange, .red] }
        return ThresholdLevel.allLevels.map { Color(nsColor: WidgetPalette.threshold($0, colors: component.levelColors)) }
    }

    private var fill: AnyShapeStyle {
        switch mode {
        case .monochrome:
            AnyShapeStyle(LinearGradient(colors: [.black, .white], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .accent:
            AnyShapeStyle(Color.accentColor)
        case .threshold:
            AnyShapeStyle(AngularGradient(colors: thresholdColors + thresholdColors.prefix(1), center: .center))
        case .custom:
            AnyShapeStyle(component.customSwiftUIColor)
        case .gradient:
            AnyShapeStyle(LinearGradient(colors: [component.gradientStartSwiftUIColor, component.gradientEndSwiftUIColor],
                                         startPoint: .leading, endPoint: .trailing))
        }
    }
}
