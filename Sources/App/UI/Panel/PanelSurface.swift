import SwiftUI

extension EnvironmentValues {
    /// Panelin zemin türü; kartlar dolgusunu buna göre seçer.
    @Entry var panelBackground: PanelBackground = .glass
}

/// Panel renk paleti (opak yüzey ve kart dolguları). Koyu: #2B2B2D yüzey, #3A3A3C kart; açık: #F4F4F6 yüzey, beyaz kart.
enum PanelPalette {
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2D / 255) : Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF6 / 255)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255) : .white
    }

    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.09)
    }

    static func cardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.05) : .black.opacity(0.05)
    }

    static func highlight(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.07) : .white.opacity(0.9)
    }
}

/// Kartın zemini: opak modda düz kart rengi + ince çizgi, camda `.quaternary`.
struct PanelCardBackground: View {
    var cornerRadius: CGFloat = 14
    @Environment(\.panelBackground) private var background
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch background {
        case .solid:
            shape.fill(PanelPalette.card(scheme))
                .overlay { shape.strokeBorder(PanelPalette.cardStroke(scheme), lineWidth: 0.5) }
        case .glass:
            shape.fill(.quaternary)
        }
    }
}

/// Panelin dış yüzeyi: opak modda köşeleri yuvarlak, üstte hafif ışık, 1 pt iç çizgi. Cam modda hiçbir şey çizmez (pencere camı çizer).
struct PanelSurface: ViewModifier {
    let background: PanelBackground
    static let cornerRadius: CGFloat = 18
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        content
            .environment(\.panelBackground, background)
            .background {
                if background == .solid {
                    shape.fill(PanelPalette.surface(scheme))
                        .overlay {
                            shape.fill(LinearGradient(colors: [PanelPalette.highlight(scheme), .clear],
                                                      startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22)))
                        }
                        .overlay { shape.strokeBorder(PanelPalette.stroke(scheme), lineWidth: 1) }
                }
            }
            .clipShape(background == .solid ? AnyShape(shape) : AnyShape(Rectangle()))
    }
}

extension View {
    func panelSurface(_ background: PanelBackground) -> some View { modifier(PanelSurface(background: background)) }
}
