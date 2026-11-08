import CoreGraphics
import Foundation

/// Ofis görünümü (yalnızca doku katmanı): `vector` modern 2D vektör (4x yüksek çözünürlüklü, yumuşak kenarlı dokular, kesirli zoom),
/// `pixel` eski piksel-art (nearest, tamsayı zoom). Mantık/ızgara/koltuk/BFS temadan bağımsızdır; sahne birimi her iki temada 16 pt/karo.
enum OfficeTheme: String, CaseIterable, Sendable {
    case vector, pixel

    static let defaultsKey = "officeTheme"
    static let `default`: OfficeTheme = .vector
    /// Vektör dokuların 4x çözünürlüğü: 16 pt karo = 64 px.
    static let vectorScale = 4

    var title: String {
        switch self {
        case .vector: "Vektör"
        case .pixel: "Piksel"
        }
    }

    /// Bozuk/eksik kayıt varsayılana (vektör) düşer.
    static func stored(_ defaults: UserDefaults = .standard) -> OfficeTheme {
        defaults.string(forKey: defaultsKey).flatMap(OfficeTheme.init(rawValue:)) ?? .default
    }

    static func store(_ theme: OfficeTheme, defaults: UserDefaults = .standard) { defaults.set(theme.rawValue, forKey: defaultsKey) }

    /// Doku çözünürlüğü (mantıksal birim başına piksel).
    var textureScale: Int { self == .vector ? Self.vectorScale : 1 }
    /// Yalnızca pikselde zoom tamsayı olmak zorundadır (nearest); vektörde kesirli.
    var integerZoomOnly: Bool { self == .pixel }
    var lighting: OfficeLightParams { self == .vector ? .vector : .pixel }
}

/// Gece ışığı parametreleri (temaya göre). Piksel: eski değerler aynen. Vektör: hafif örtü + belirgin sıcak ışık havuzları.
struct OfficeLightParams: Equatable, Sendable {
    /// Çarpan (multiply) örtü rengi (0-1) ve alfa.
    var overlayRGB: [Double]
    var overlayAlpha: Double
    /// Tavan lambası, masa ışık havuzu, tahta havuzu, PC ekran parıltısı (additive sprite alfaları).
    var bulbAlpha: Double
    var poolAlpha: Double
    var boardAlpha: Double
    var screenAlpha: Double
    /// Pencere dışından gelen ay ışığı (additive, mavi) alfası; 0: yok.
    var windowAlpha: Double

    /// SpriteKit `.multiply` sprite alfasını yok sayar (hedef × renk). Piksel: eski davranış aynen (renk + alfa). Vektör: okunur alacakaranlık
    /// çarpanı (düğüm alfası 1) + `overlayRGB` laciverti `overlayAlpha` ile normal karışımda ince bir tonlama (wash).
    var multiplyColor: [Double] { isVectorLike ? Self.duskFactor : overlayRGB }
    var multiplyNodeAlpha: Double { isVectorLike ? 1 : overlayAlpha }
    var hasWash: Bool { isVectorLike }
    static let duskFactor: [Double] = [0.60, 0.66, 0.88]
    private var isVectorLike: Bool { windowAlpha > 0 }

    static let pixel = OfficeLightParams(overlayRGB: [0.14, 0.18, 0.40], overlayAlpha: OfficeLighting.nightOverlayAlpha,
                                         bulbAlpha: 0.85, poolAlpha: 0.9, boardAlpha: 0.5, screenAlpha: 1, windowAlpha: 0)
    static let vector = OfficeLightParams(overlayRGB: [0.05, 0.10, 0.34], overlayAlpha: 0.22,
                                          bulbAlpha: 0.38, poolAlpha: 0.40, boardAlpha: 0.30, screenAlpha: 0.9, windowAlpha: 0.22)
}
