import AppKit

/// Codable sRGB renk (bileşenler 0...1).
struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    /// "#RRGGBB" ya da "#RRGGBBAA".
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacing("#", with: "")
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let full = s.count == 6 ? (v << 8) | 0xFF : v
        red = Double((full >> 24) & 0xFF) / 255
        green = Double((full >> 16) & 0xFF) / 255
        blue = Double((full >> 8) & 0xFF) / 255
        alpha = Double(full & 0xFF) / 255
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `t` = 0 → self, `t` = 1 → other; arada doğrusal.
    func interpolated(to other: RGBAColor, fraction t: Double) -> RGBAColor {
        let k = max(0, min(1, t))
        return RGBAColor(red: red + (other.red - red) * k,
                         green: green + (other.green - green) * k,
                         blue: blue + (other.blue - blue) * k,
                         alpha: alpha + (other.alpha - alpha) * k)
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        self.init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
    }

    static let teal = RGBAColor(red: 0.19, green: 0.69, blue: 0.78)
    static let green = RGBAColor(red: 0.20, green: 0.78, blue: 0.35)
    static let red = RGBAColor(red: 1.0, green: 0.27, blue: 0.23)
    static let blue = RGBAColor(red: 0.04, green: 0.52, blue: 1.0)
}
