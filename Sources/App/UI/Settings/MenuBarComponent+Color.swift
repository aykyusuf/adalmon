import AppKit
import SwiftUI

extension MenuBarComponent {
    var customSwiftUIColor: Color {
        get { Color(nsColor: customColor.nsColor) }
        set { customColor = RGBAColor(NSColor(newValue)) }
    }

    var gradientStartSwiftUIColor: Color {
        get { Color(nsColor: gradientStart.nsColor) }
        set { gradientStart = RGBAColor(NSColor(newValue)) }
    }

    var gradientEndSwiftUIColor: Color {
        get { Color(nsColor: gradientEnd.nsColor) }
        set { gradientEnd = RGBAColor(NSColor(newValue)) }
    }
}
