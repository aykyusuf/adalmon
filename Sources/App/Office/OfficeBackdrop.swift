import CoreGraphics
import Foundation
import SpriteKit

/// Ofis sahnesinin arka planı (odaların dışında kalan alan). `solid`: düz renk (piksel tema / `Koyu` / `Açık`); `themed`: vektör temada
/// gündüz sıcak krem → bej, gece lacivert → mor-lacivert gradyan (+ çok hafif doku, vinyet). Piksel temada `themed` eski koyu zemine düşer.
enum OfficeBackdropStyle: Equatable, Sendable {
    case solid(OfficeRGB)
    case themed

    /// Sahnenin eski düz zemini (#12131A).
    static let defaultSolid = OfficeRGB(r: 0.075, g: 0.075, b: 0.095)
}

/// Arka plan renk/doku parametreleri (saf veri). Gündüz: açık sıcak, düşük kontrast zemin tahtası dokusu; gece: yıldız + bokeh noktaları.
struct OfficeBackdropPalette: Equatable, Sendable {
    var top: OfficeRGB
    var bottom: OfficeRGB
    /// Ortadaki (odaların arkasındaki) yumuşak sıcak parıltı.
    var glow: OfficeRGB
    var glowAlpha: Double
    /// Kenar/köşe vinyeti.
    var vignette: OfficeRGB
    var vignetteAlpha: Double
    /// Zemin tahtası dokusu (gündüz): koyu ton alfası; 0: yok.
    var plankAlpha: Double
    /// Yıldız sayısı ve bokeh sayısı (gece); 0: yok.
    var stars: Int
    var bokeh: Int

    static let day = OfficeBackdropPalette(top: OfficeRGB(r: 0.984, g: 0.957, b: 0.902), bottom: OfficeRGB(r: 0.902, g: 0.835, b: 0.722),
                                           glow: OfficeRGB(r: 1.0, g: 0.953, b: 0.855), glowAlpha: 0.55,
                                           vignette: OfficeRGB(r: 0.66, g: 0.54, b: 0.36), vignetteAlpha: 0.20,
                                           plankAlpha: 0.08, stars: 0, bokeh: 0)
    static let night = OfficeBackdropPalette(top: OfficeRGB(r: 0.039, g: 0.063, b: 0.188), bottom: OfficeRGB(r: 0.145, g: 0.106, b: 0.290),
                                             glow: OfficeRGB(r: 1.0, g: 0.69, b: 0.40), glowAlpha: 0.13,
                                             vignette: OfficeRGB(r: 0.012, g: 0.016, b: 0.06), vignetteAlpha: 0.50,
                                             plankAlpha: 0, stars: 170, bokeh: 16)

    static func palette(night: Bool) -> OfficeBackdropPalette { night ? .night : .day }

    /// Algısal parlaklık (0…1) — testler gündüz açık / gece koyu aralığını doğrular.
    static func luminance(_ c: OfficeRGB) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

    /// Doku çözünürlüğü: uzun kenar bu pikseli aşmaz (4K/5K'da bile ~3,7 MB); gradyan/bokeh yumuşak olduğundan büyütme kayıpsızdır.
    static let maxTextureEdge = 1280.0

    /// Görünüm boyutundan (nokta) doku piksel boyutu; en-boy oranı 0,05 adımlarında sabitlenir (canlı yeniden boyutlamada yeniden üretim azalır).
    static func textureSize(for view: CGSize) -> (width: Int, height: Int, bucket: Int) {
        let aspect = min(4, max(0.4, view.width / max(view.height, 1)))
        let bucket = Int((aspect * 20).rounded())
        let a = Double(bucket) / 20
        if a >= 1 { return (Int(maxTextureEdge), max(1, Int((maxTextureEdge / a).rounded())), bucket) }
        return (max(1, Int((maxTextureEdge * a).rounded())), Int(maxTextureEdge), bucket)
    }
}

/// Deterministik rastgele (aynı tohum → aynı yıldız dizilimi; testler/önizleme kararlı).
struct OfficeBackdropRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
}

enum OfficeBackdropRenderer {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func color(_ c: OfficeRGB, _ a: Double = 1) -> CGColor { CGColor(colorSpace: space, components: [c.r, c.g, c.b, a])! }

    /// Arka plan görüntüsü (y yukarı bağlam; `top` görüntünün üstünde).
    static func image(palette p: OfficeBackdropPalette, width w: Int, height h: Int, seed: UInt64 = 7) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let W = Double(w), H = Double(h), s = H / 720
        var rng = OfficeBackdropRNG(seed: seed)
        // 1) Çapraz gradyan.
        let grad = CGGradient(colorsSpace: space, colors: [color(p.top), color(p.bottom)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: W * 0.15, y: H), end: CGPoint(x: W * 0.85, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // 2) Gündüz: büyük, düşük kontrastlı zemin tahtası dokusu (şeritler + kaydırmalı derzler).
        if p.plankAlpha > 0 {
            let rows = 9, ph = H / Double(rows)
            for r in 0..<rows {
                if r % 2 == 0 {
                    ctx.setFillColor(color(OfficeRGB(r: 0.45, g: 0.32, b: 0.16), p.plankAlpha * 0.45))
                    ctx.fill(CGRect(x: 0, y: Double(r) * ph, width: W, height: ph))
                }
                ctx.setFillColor(color(OfficeRGB(r: 0.45, g: 0.32, b: 0.16), p.plankAlpha))
                ctx.fill(CGRect(x: 0, y: Double(r) * ph, width: W, height: max(1, s)))
                let pw = W / 4.2
                var x = -rng.range(0, pw)
                while x < W {
                    ctx.fill(CGRect(x: x, y: Double(r) * ph, width: max(1, s), height: ph))
                    x += pw * rng.range(0.85, 1.15)
                }
            }
        }
        // 3) Orta sıcak parıltı (odaların arkası).
        let glow = CGGradient(colorsSpace: space, colors: [color(p.glow, p.glowAlpha), color(p.glow, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W / 2, y: H * 0.52), startRadius: 0, endCenter: CGPoint(x: W / 2, y: H * 0.52), endRadius: max(W, H) * 0.62, options: [])
        // 4) Gece: yıldızlar (üst yarıda yoğun) + bokeh "şehir ışığı" noktaları (alt şeritte yoğun).
        if p.stars > 0 {
            for _ in 0..<p.stars {
                let x = rng.range(0, W), y = H * (1 - pow(rng.next(), 1.6))
                let r = rng.range(0.6, 1.7) * s
                ctx.setFillColor(color(OfficeRGB(r: 0.86, g: 0.9, b: 1), rng.range(0.10, 0.42)))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        if p.bokeh > 0 {
            let tones = [OfficeRGB(r: 1, g: 0.72, b: 0.42), OfficeRGB(r: 0.45, g: 0.8, b: 0.95), OfficeRGB(r: 0.72, g: 0.55, b: 1)]
            for i in 0..<p.bokeh {
                let low = i % 3 != 0
                let x = rng.range(0, W), y = low ? rng.range(0, H * 0.3) : rng.range(H * 0.3, H)
                let r = rng.range(9, 28) * s
                let tone = tones[i % tones.count]
                let g = CGGradient(colorsSpace: space, colors: [color(tone, rng.range(0.05, 0.10)), color(tone, 0)] as CFArray, locations: [0.55, 1])!
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
            }
        }
        // 5) Kenar vinyeti: merkez saydam, köşeler p.vignette.
        let vig = CGGradient(colorsSpace: space, colors: [color(p.vignette, 0), color(p.vignette, 0), color(p.vignette, p.vignetteAlpha)] as CFArray, locations: [0, 0.55, 1])!
        let vr = (W * W + H * H).squareRoot() / 2
        ctx.drawRadialGradient(vig, startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: 0, endCenter: CGPoint(x: W / 2, y: H / 2), endRadius: vr, options: [.drawsAfterEndLocation])
        return ctx.makeImage()
    }

    /// Oda gölgesi/parıltısı: gövde dikdörtgeninin (w×h dünya birimi) çevresinde `pad` kadar yumuşak gölge; gövdenin kendisi şeffaf bırakılır.
    /// Gündüz sıcak kahverengi alt gölge, gece sıcak amber parıltı.
    static func roomShadow(width: Double, height: Double, pad: Double, night: Bool, scale: Double = 2) -> CGImage? {
        let w = Int(((width + 2 * pad) * scale).rounded(.up)), h = Int(((height + 2 * pad) * scale).rounded(.up))
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let body = CGRect(x: pad * scale, y: pad * scale, width: width * scale, height: height * scale)
        ctx.saveGState()
        if night {
            ctx.setShadow(offset: .zero, blur: pad * scale * 0.9, color: color(OfficeRGB(r: 1, g: 0.70, b: 0.38), 0.40))
        } else {
            ctx.setShadow(offset: CGSize(width: 0, height: -pad * scale * 0.28), blur: pad * scale * 0.8, color: color(OfficeRGB(r: 0.30, g: 0.20, b: 0.08), 0.38))
        }
        ctx.setFillColor(color(.init(r: 0, g: 0, b: 0)))
        ctx.fill(body)
        ctx.restoreGState()
        ctx.setBlendMode(.clear)
        ctx.fill(body)
        return ctx.makeImage()
    }
}

/// Sahne arkası görsel düğümü (kamera çocuğu: kamera ölçeğinden/konumundan etkilenmez, ekranı doldurur). İki sprite ile 1 sn çapraz geçiş.
@MainActor
final class OfficeBackdropNode: SKNode {
    static let zPos: CGFloat = -100_000
    private let base = SKSpriteNode()
    private let overlay = SKSpriteNode()
    private(set) var night: Bool
    private(set) var viewSize: CGSize
    private var bucket = 0
    private static var cache: [String: SKTexture] = [:]

    init(size: CGSize, night: Bool) {
        self.night = night
        viewSize = size
        super.init()
        zPosition = Self.zPos
        for s in [base, overlay] { s.anchorPoint = CGPoint(x: 0.5, y: 0.5); s.size = size; s.zPosition = 0; addChild(s) }
        overlay.zPosition = 1
        overlay.alpha = 0
        bucket = OfficeBackdropPalette.textureSize(for: size).bucket
        base.texture = Self.texture(night: night, view: size)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) yok") }

    static func texture(night: Bool, view: CGSize) -> SKTexture? {
        let t = OfficeBackdropPalette.textureSize(for: view)
        let key = "\(night ? "n" : "d")\(t.width)x\(t.height)"
        if let hit = cache[key] { return hit }
        guard let img = OfficeBackdropRenderer.image(palette: .palette(night: night), width: t.width, height: t.height) else { return nil }
        let tex = SKTexture(cgImage: img)
        tex.filteringMode = .linear
        if cache.count >= 6 { cache.removeAll() }
        cache[key] = tex
        return tex
    }

    /// Boyut değişince sprite hemen uzar; doku yalnızca en-boy oranı kovası değişince yeniden üretilir.
    func setSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != viewSize else { return }
        viewSize = size
        base.size = size; overlay.size = size
        let b = OfficeBackdropPalette.textureSize(for: size).bucket
        if b != bucket {
            bucket = b
            base.texture = Self.texture(night: night, view: size)
            overlay.removeAllActions(); overlay.alpha = 0
        }
    }

    /// Gündüz ↔ gece: animasyonluysa 1 sn çapraz geçiş (üstteki sprite belirir, bitince alttaki yenilenir).
    func setNight(_ newNight: Bool, animated: Bool) {
        guard newNight != night else { return }
        night = newNight
        overlay.removeAllActions()
        guard let tex = Self.texture(night: newNight, view: viewSize) else { return }
        if animated {
            overlay.texture = tex
            overlay.alpha = 0
            overlay.run(.sequence([.fadeIn(withDuration: OfficeLighting.crossfade), .run { [weak self] in
                self?.base.texture = tex
                self?.overlay.alpha = 0
            }]), withKey: "fade")
        } else {
            base.texture = tex
            overlay.alpha = 0
        }
    }
}

/// Odanın çevresindeki yumuşak gölge (gündüz) / sıcak parıltı (gece): iki sprite, ışık değişince çapraz geçiş. Odanın kökünde, odanın altında durur.
@MainActor
final class OfficeRoomShadow: SKNode {
    static let pad: Double = 36
    private let day = SKSpriteNode()
    private let nightSprite = SKSpriteNode()
    private static var cache: [String: SKTexture] = [:]

    init(bodySize: CGSize, night: Bool) {
        super.init()
        zPosition = -1
        for (s, n) in [(day, false), (nightSprite, true)] {
            s.anchorPoint = .zero
            s.position = CGPoint(x: -Self.pad, y: -Self.pad)
            s.size = CGSize(width: bodySize.width + 2 * Self.pad, height: bodySize.height + 2 * Self.pad)
            s.texture = Self.texture(size: bodySize, night: n)
            addChild(s)
        }
        setNight(night, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) yok") }

    private static func texture(size: CGSize, night: Bool) -> SKTexture? {
        let key = "\(Int(size.width))x\(Int(size.height))\(night ? "n" : "d")"
        if let hit = cache[key] { return hit }
        guard let img = OfficeBackdropRenderer.roomShadow(width: size.width, height: size.height, pad: pad, night: night) else { return nil }
        let tex = SKTexture(cgImage: img)
        tex.filteringMode = .linear
        cache[key] = tex
        return tex
    }

    func setNight(_ night: Bool, animated: Bool) {
        let (show, hide) = night ? (nightSprite, day) : (day, nightSprite)
        for s in [show, hide] { s.removeAllActions() }
        if animated {
            show.run(.fadeIn(withDuration: OfficeLighting.crossfade)); hide.run(.fadeOut(withDuration: OfficeLighting.crossfade))
        } else {
            show.alpha = 1; hide.alpha = 0
        }
    }
}
