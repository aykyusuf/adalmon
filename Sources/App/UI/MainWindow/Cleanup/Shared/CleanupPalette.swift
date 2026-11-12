import SwiftUI

/// Temizlik tasarım kiti: bölüm vurgu rengi. Her bölümün tek bir vurgusu vardır; kit bileşenleri bu yapıyı alır ve
/// açık / koyu tonları (`light`, `deep`) kendisi türetir.
///
/// Kullanım: `CleanupHero3D(symbol: "trash", accent: CleanupSubsection.junk.accent, ...)`.
struct CleanupAccent: Equatable, Sendable {
    var hue: Double
    var saturation: Double
    var brightness: Double

    /// `lift` > 0 daha açık ve soluk, < 0 daha koyu ve doygun.
    func color(lift: Double = 0) -> Color {
        Color(hue: hue, saturation: min(1, max(0, saturation - lift * 0.25)), brightness: min(1, max(0, brightness + lift)))
    }

    var base: Color { color() }
    var light: Color { color(lift: 0.16) }
    var deep: Color { color(lift: -0.22) }

    /// Işıklı üst-sol köşeden koyu alt-sağ köşeye ana gradyan.
    var gradient: LinearGradient {
        LinearGradient(colors: [light, base, deep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let smartScan = CleanupAccent(hue: 0.73, saturation: 0.62, brightness: 0.92)
    static let junk = CleanupAccent(hue: 0.07, saturation: 0.78, brightness: 0.98)
    static let dev = CleanupAccent(hue: 0.52, saturation: 0.70, brightness: 0.88)
    static let uninstaller = CleanupAccent(hue: 0.93, saturation: 0.58, brightness: 0.95)
    static let largeOld = CleanupAccent(hue: 0.60, saturation: 0.68, brightness: 0.95)
    static let duplicates = CleanupAccent(hue: 0.79, saturation: 0.55, brightness: 0.90)
    static let privacy = CleanupAccent(hue: 0.40, saturation: 0.62, brightness: 0.80)
    static let spaceLens = CleanupAccent(hue: 0.47, saturation: 0.66, brightness: 0.82)
    static let startup = CleanupAccent(hue: 0.13, saturation: 0.80, brightness: 0.96)
    static let maintenance = CleanupAccent(hue: 0.62, saturation: 0.32, brightness: 0.78)
}

extension CleanupSubsection {
    /// Bölümün vurgu rengi (kahraman, halka, düğme, kart ikonları).
    var accent: CleanupAccent {
        switch self {
        case .smartScan: .smartScan
        case .junk: .junk
        case .dev: .dev
        case .uninstaller: .uninstaller
        case .largeOld: .largeOld
        case .duplicates: .duplicates
        case .privacy: .privacy
        case .spaceLens: .spaceLens
        case .startup: .startup
        case .maintenance: .maintenance
        }
    }
}

/// Büyük birincil düğme: vurgu gradyanlı kapsül, basınca hafif küçülür.
struct CleanupPrimaryButtonStyle: ButtonStyle {
    let accent: CleanupAccent
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(prominent ? .title3.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, prominent ? 30 : 18)
            .padding(.vertical, prominent ? 12 : 8)
            .background(Capsule().fill(accent.gradient))
            .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
            .shadow(color: accent.deep.opacity(isEnabled ? 0.45 : 0), radius: prominent ? 12 : 6, y: prominent ? 6 : 3)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

private struct CleanupStaticArtworkKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Anlık görüntü testleri için: 3D eğim ve kutlama animasyonu kapanır, son hâl çizilir (offscreen render 3D katmanları çizemez).
    var cleanupStaticArtwork: Bool {
        get { self[CleanupStaticArtworkKey.self] }
        set { self[CleanupStaticArtworkKey.self] = newValue }
    }
}
