import CoreGraphics
import Foundation
import SpriteKit

// Ofis kedisi çizimi: parametrik yan görünüm (sağa bakar; sola giderken sprite yatay yansıtılır).
// Poz modeli misak-app'teki kediden uyarlandı (yalnızca OKUNDU; Flutter Canvas → CoreGraphics): gövde elipsi + kafa + 4 bacak + kuyruk zinciri,
// göz/ağız durumları, tımar için kalkık ön pati:
//   /Users/yusufayik/Development/projects/misak-app/lib/features/quran/presentation/widgets/nur_cat/cat_pose.dart (CatPose, duruşlar)
// Görsel dosya yok: tüm kareler kodla üretilir, tembel önbelleğe alınır (≈25 kare × gündüz/gece).

enum OfficeCatArt {
    /// Mantıksal tuval (dünya birimi; karo = 16): kedi ≈ 1,3 karo uzunluğunda.
    static let canvasW = 28
    static let canvasH = 22
    /// Zemin çizgisi (tuvalde y, aşağı) — sprite çapası buradan hesaplanır.
    static let groundY: CGFloat = 21.4

    enum Eyes { case open, closed, happy, wide }

    struct Leg {
        var hip: CGPoint
        var foot: CGPoint
        var far = false
    }

    struct Spec {
        var body = CGPoint(x: 12, y: 11.4)
        var rx: CGFloat = 6.8
        var ry: CGFloat = 3.5
        var rot: CGFloat = 0
        var head = CGPoint(x: 20.4, y: 7.6)
        var headR: CGFloat = 3.1
        var headRot: CGFloat = 0
        var eyes = Eyes.open
        var mouthOpen: CGFloat = 0
        var tongue = false
        var earsBack = false
        var legs: [Leg] = []
        var tail: [CGPoint] = []
        var tailW: CGFloat = 1.8
        var puff: CGFloat = 1
        var haunch: CGPoint?
        var zs = false
    }

    // MARK: Renkler

    static let base = CGColor(srgbRed: 0.851, green: 0.529, blue: 0.227, alpha: 1)       // zencefil
    static let dark = CGColor(srgbRed: 0.639, green: 0.337, blue: 0.110, alpha: 1)       // çizgiler
    static let farBase = CGColor(srgbRed: 0.690, green: 0.420, blue: 0.170, alpha: 1)
    static let light = CGColor(srgbRed: 0.980, green: 0.906, blue: 0.808, alpha: 1)      // göğüs/pati
    static let pink = CGColor(srgbRed: 0.941, green: 0.569, blue: 0.557, alpha: 1)
    static let ink = CGColor(srgbRed: 0.145, green: 0.098, blue: 0.067, alpha: 1)
    static let eyeGreen = CGColor(srgbRed: 0.545, green: 0.800, blue: 0.325, alpha: 1)

    // MARK: Pozlar

    private static let ground: CGFloat = 19

    private static func stand(_ legs: [Leg]) -> Spec {
        var s = Spec()
        s.legs = legs
        s.tail = [CGPoint(x: 5.6, y: 10.2), CGPoint(x: 2.4, y: 8.6), CGPoint(x: 1.0, y: 5.4), CGPoint(x: 2.0, y: 2.8)]
        return s
    }

    private static func standLegs(_ f: Int, run: Bool = false) -> [Leg] {
        // 4 kare: (yakın arka, yakın ön, uzak arka, uzak ön) faz kaydırmalı.
        let phases: [CGFloat] = [0, 0.5, 0.5, 0]
        let hips: [CGPoint] = [CGPoint(x: 8, y: 13), CGPoint(x: 16.4, y: 13), CGPoint(x: 9.6, y: 13), CGPoint(x: 17.8, y: 13)]
        let baseX: [CGFloat] = [7.6, 16.8, 10.2, 18.4]
        return (0..<4).map { i in
            let p = (CGFloat(f) / 4 + phases[i]).truncatingRemainder(dividingBy: 1)
            let swing = sin(p * 2 * .pi)
            let lift = max(0, cos(p * 2 * .pi))
            return Leg(hip: hips[i], foot: CGPoint(x: baseX[i] + swing * 2.2, y: ground - lift * 1.8), far: i >= 2)
        }
    }

    static func spec(_ pose: OfficeCatPose, frame f: Int) -> Spec {
        switch pose {
        case .stand:
            let bx: [CGFloat] = [7.6, 16.8, 10.2, 18.4]
            return stand(standLegs(0).enumerated().map { i, l in Leg(hip: l.hip, foot: CGPoint(x: bx[i], y: ground), far: l.far) })
        case .walk:
            var s = stand(standLegs(f))
            s.body.y = 11.4 + (f % 2 == 0 ? 0 : 0.4)
            s.head.y = 7.6 + (f % 2 == 0 ? 0 : 0.35)
            s.tail = [CGPoint(x: 5.6, y: 10.2), CGPoint(x: 2.6, y: 9.0 + CGFloat(f % 2) * 0.6), CGPoint(x: 0.9, y: 6.6), CGPoint(x: 1.4, y: 4.0 + CGFloat(f % 2) * 0.8)]
            return s
        case .run:
            var s = Spec()
            s.rx = 7.4; s.ry = 3.0; s.body = CGPoint(x: 12.5, y: 11.6); s.head = CGPoint(x: 21.8, y: 9.0); s.headR = 3.0
            if f == 0 {
                s.legs = [Leg(hip: CGPoint(x: 7, y: 12.8), foot: CGPoint(x: 1.8, y: 16.6)), Leg(hip: CGPoint(x: 17.5, y: 12.8), foot: CGPoint(x: 23.2, y: 16.2)),
                          Leg(hip: CGPoint(x: 8.4, y: 12.8), foot: CGPoint(x: 3.8, y: 17.8), far: true), Leg(hip: CGPoint(x: 18.8, y: 12.8), foot: CGPoint(x: 24.2, y: 17.4), far: true)]
            } else {
                s.legs = [Leg(hip: CGPoint(x: 8, y: 12.8), foot: CGPoint(x: 13.6, y: ground)), Leg(hip: CGPoint(x: 16.5, y: 12.8), foot: CGPoint(x: 11.4, y: ground - 0.4)),
                          Leg(hip: CGPoint(x: 9.4, y: 12.8), foot: CGPoint(x: 14.8, y: ground - 0.8), far: true), Leg(hip: CGPoint(x: 17.8, y: 12.8), foot: CGPoint(x: 12.4, y: ground - 0.6), far: true)]
                s.body.y = 12.4; s.head.y = 9.8
            }
            s.tail = [CGPoint(x: 5.6, y: 10.4), CGPoint(x: 2.6, y: 10.0), CGPoint(x: -0.4, y: 9.2), CGPoint(x: -1.4, y: 8.6)]
            return s
        case .sit, .sitTail, .happy, .alert:
            return sitSpec(pose, f)
        case .groomFace:
            var s = sitSpec(.sit, 0)
            s.eyes = .closed
            s.head = CGPoint(x: 16.4, y: 8.4 + CGFloat(f) * 0.4); s.headRot = 0.35
            s.legs[0] = Leg(hip: CGPoint(x: 15.4, y: 12.4), foot: CGPoint(x: 18.8 - CGFloat(f) * 1.2, y: 9.6 - CGFloat(f) * 2.0))
            return s
        case .groomChest:
            var s = sitSpec(.sit, 0)
            s.eyes = .closed
            s.head = CGPoint(x: 15.6 + CGFloat(f) * 0.6, y: 10.0 + CGFloat(f) * 0.6); s.headRot = 0.7
            s.tongue = f == 1
            return s
        case .lick:
            var s = sitSpec(.sit, 0)
            s.headRot = 0.2; s.head = CGPoint(x: 17.3, y: 6.3 + CGFloat(f) * 0.6)
            s.eyes = f == 0 ? .open : .closed; s.tongue = f == 1
            return s
        case .yawn:
            var s = sitSpec(.sit, 0)
            s.eyes = .closed; s.mouthOpen = 1; s.headRot = -0.45; s.head = CGPoint(x: 17.3, y: 5.2)
            return s
        case .stretch:
            var s = Spec()
            s.body = CGPoint(x: 12.5, y: 11.2); s.rot = 0.26; s.rx = 7; s.ry = 3.3
            s.head = CGPoint(x: 22.2, y: 14.6); s.headRot = 0.5; s.eyes = .closed
            s.legs = [Leg(hip: CGPoint(x: 7.4, y: 10.6), foot: CGPoint(x: 7.0, y: ground)), Leg(hip: CGPoint(x: 17, y: 13.4), foot: CGPoint(x: 25.2, y: 18.8)),
                      Leg(hip: CGPoint(x: 8.8, y: 10.8), foot: CGPoint(x: 8.8, y: ground), far: true), Leg(hip: CGPoint(x: 18.2, y: 13.6), foot: CGPoint(x: 26.4, y: 18.4), far: true)]
            s.tail = [CGPoint(x: 5.4, y: 8.4), CGPoint(x: 2.8, y: 5.4), CGPoint(x: 1.4, y: 2.4), CGPoint(x: 2.2, y: 0.4)]
            return s
        case .crouch:
            var s = Spec()
            s.body = CGPoint(x: 12.4, y: 15.0); s.rx = 7.2; s.ry = 2.9; s.rot = -0.06
            s.head = CGPoint(x: 20.6, y: 13.4); s.headR = 3.0; s.eyes = .wide
            s.legs = [Leg(hip: CGPoint(x: 7.6, y: 15.4), foot: CGPoint(x: 8.6, y: ground)), Leg(hip: CGPoint(x: 16.6, y: 16), foot: CGPoint(x: 21.4, y: ground)),
                      Leg(hip: CGPoint(x: 9, y: 15.4), foot: CGPoint(x: 10.4, y: ground), far: true), Leg(hip: CGPoint(x: 17.6, y: 16), foot: CGPoint(x: 22.6, y: ground), far: true)]
            s.tail = [CGPoint(x: 5.4, y: 14.6), CGPoint(x: 2.2, y: 16.0), CGPoint(x: 0.4, y: 17.6), CGPoint(x: -0.6, y: 16.2)]
            return s
        case .leapUp:
            var s = Spec()
            s.body = CGPoint(x: 12.5, y: 11.4); s.rot = -0.5; s.rx = 7.4; s.ry = 3.0
            s.head = CGPoint(x: 21.4, y: 6.0); s.headRot = -0.3; s.eyes = .wide
            s.legs = [Leg(hip: CGPoint(x: 7, y: 14), foot: CGPoint(x: 2.4, y: 18.0)), Leg(hip: CGPoint(x: 17, y: 9.4), foot: CGPoint(x: 24.2, y: 5.8)),
                      Leg(hip: CGPoint(x: 8.4, y: 14), foot: CGPoint(x: 4.4, y: 19), far: true), Leg(hip: CGPoint(x: 18, y: 9.8), foot: CGPoint(x: 25.4, y: 7.4), far: true)]
            s.tail = [CGPoint(x: 5.4, y: 13), CGPoint(x: 2.6, y: 15.4), CGPoint(x: 0.4, y: 17.0), CGPoint(x: -1.0, y: 17.4)]
            return s
        case .leapDown:
            var s = Spec()
            s.body = CGPoint(x: 12.5, y: 10.6); s.rot = 0.4; s.rx = 7.2; s.ry = 3.2
            s.head = CGPoint(x: 21.6, y: 12.6); s.headRot = 0.4; s.eyes = .wide
            s.legs = [Leg(hip: CGPoint(x: 7.4, y: 9.6), foot: CGPoint(x: 3.6, y: 13.4)), Leg(hip: CGPoint(x: 17.4, y: 14), foot: CGPoint(x: 22.8, y: 19.0)),
                      Leg(hip: CGPoint(x: 8.8, y: 9.8), foot: CGPoint(x: 5.6, y: 14.6), far: true), Leg(hip: CGPoint(x: 18.6, y: 14.2), foot: CGPoint(x: 24.4, y: 18.2), far: true)]
            s.tail = [CGPoint(x: 5.2, y: 8.2), CGPoint(x: 2.6, y: 5.6), CGPoint(x: 0.6, y: 4.0), CGPoint(x: 0.2, y: 2.4)]
            return s
        case .loaf:
            var s = Spec()
            s.body = CGPoint(x: 12.4, y: 15.6); s.rx = 7.4; s.ry = 4.2
            s.head = CGPoint(x: 19.6, y: 13.2); s.headR = 3.0; s.eyes = .closed
            s.legs = [Leg(hip: CGPoint(x: 19, y: 18), foot: CGPoint(x: 23.2, y: ground), far: false)]
            s.tail = [CGPoint(x: 5.2, y: 17.8), CGPoint(x: 9.0, y: 19.6), CGPoint(x: 15, y: 19.8), CGPoint(x: 20.6, y: 19.2)]
            return s
        case .lieKeys:
            var s = Spec()
            s.body = CGPoint(x: 11.6, y: 16.2); s.rx = 8.2; s.ry = 3.2
            s.head = CGPoint(x: 20.8, y: 15.0); s.headR = 3.0; s.headRot = 0.2; s.eyes = .closed
            s.legs = [Leg(hip: CGPoint(x: 17, y: 17.8), foot: CGPoint(x: 25.4, y: 19.2)), Leg(hip: CGPoint(x: 18, y: 18), foot: CGPoint(x: 26.6, y: 18.2), far: true)]
            s.tail = [CGPoint(x: 4.0, y: 16.6), CGPoint(x: 1.6, y: 17.8), CGPoint(x: -0.4, y: 18.8), CGPoint(x: -1.4, y: 18.0)]
            return s
        case .sleep:
            var s = Spec()
            s.body = CGPoint(x: 13.2, y: 14.4); s.rx = 7.2; s.ry = 4.9
            s.head = CGPoint(x: 18.6, y: 16.0); s.headR = 2.9; s.headRot = 0.5; s.eyes = .closed
            s.tail = [CGPoint(x: 6.6, y: 17.6), CGPoint(x: 9.8, y: 19.7), CGPoint(x: 15.4, y: 19.8), CGPoint(x: 20.4, y: 18.6)]
            s.zs = true
            return s
        }
    }

    private static func sitSpec(_ pose: OfficeCatPose, _ f: Int) -> Spec {
        var s = Spec()
        s.body = CGPoint(x: 11.6, y: 12.6); s.rx = 6.6; s.ry = 4.0; s.rot = -0.95
        s.head = CGPoint(x: 17.4, y: 6.4); s.headR = 3.1
        s.haunch = CGPoint(x: 9.2, y: 15.4)
        s.legs = [Leg(hip: CGPoint(x: 15.4, y: 12.2), foot: CGPoint(x: 16.6, y: ground)), Leg(hip: CGPoint(x: 16.8, y: 12.4), foot: CGPoint(x: 18.2, y: ground), far: true)]
        s.tail = [CGPoint(x: 6.6, y: 17.6), CGPoint(x: 3.8, y: 18.6), CGPoint(x: 1.2, y: 18.2), CGPoint(x: 0.4, y: 16.2)]
        switch pose {
        case .sitTail:
            s.tail = f == 0 ? [CGPoint(x: 6.6, y: 17.4), CGPoint(x: 3.4, y: 18.2), CGPoint(x: 1.0, y: 16.2), CGPoint(x: 1.6, y: 13.6)]
                            : [CGPoint(x: 6.6, y: 17.4), CGPoint(x: 3.6, y: 18.6), CGPoint(x: 0.8, y: 17.6), CGPoint(x: -0.2, y: 15.2)]
        case .happy:
            s.eyes = .happy
            s.tail = [CGPoint(x: 6.6, y: 17.2), CGPoint(x: 3.2, y: 16.4), CGPoint(x: 1.6, y: 12.6), CGPoint(x: 2.8, y: 9.6)]
        case .alert:
            s.body = CGPoint(x: 12.4, y: 10.4); s.rx = 6.6; s.ry = 4.8; s.rot = 0; s.puff = 1.18
            s.head = CGPoint(x: 19.8, y: 9.6); s.headRot = 0.35; s.eyes = .wide; s.earsBack = true; s.haunch = nil
            s.legs = [Leg(hip: CGPoint(x: 8, y: 12.6), foot: CGPoint(x: 7.2, y: ground)), Leg(hip: CGPoint(x: 15.6, y: 12.6), foot: CGPoint(x: 17.4, y: ground)),
                      Leg(hip: CGPoint(x: 9.6, y: 12.6), foot: CGPoint(x: 9.8, y: ground), far: true), Leg(hip: CGPoint(x: 17.2, y: 12.6), foot: CGPoint(x: 19.2, y: ground), far: true)]
            s.tail = [CGPoint(x: 5.8, y: 8.8), CGPoint(x: 3.4, y: 5.4), CGPoint(x: 2.4, y: 2.4), CGPoint(x: 3.6, y: 0.4)]
            s.tailW = 3.0
        default:
            break
        }
        return s
    }

    // MARK: Çizim

    static func image(_ pose: OfficeCatPose, frame: Int, scale: Int, antialias: Bool = true) -> CGImage? {
        draw(spec(pose, frame: frame), scale: scale, antialias: antialias)
    }

    static func draw(_ s: Spec, scale: Int, antialias: Bool = true) -> CGImage? {
        OfficeVectorArt.render(canvasW, canvasH, scale: scale) { c in
            c.setShouldAntialias(antialias)
            c.translateBy(x: 0, y: groundY - ground)
            c.setLineCap(.round); c.setLineJoin(.round)
            for l in s.legs where l.far { leg(c, l, color: farBase) }
            tail(c, s)
            body(c, s)
            for l in s.legs where !l.far { leg(c, l, color: base) }
            head(c, s)
            if s.zs { zz(c) }
        }
    }

    private static func leg(_ c: CGContext, _ l: Leg, color: CGColor) {
        c.setStrokeColor(color); c.setLineWidth(2.0)
        c.move(to: l.hip); c.addLine(to: l.foot); c.strokePath()
        c.setFillColor(light)
        c.fillEllipse(in: CGRect(x: l.foot.x - 1.5, y: l.foot.y - 1.0, width: 3.0, height: 1.7))
    }

    private static func tail(_ c: CGContext, _ s: Spec) {
        guard s.tail.count >= 2 else { return }
        c.setStrokeColor(base); c.setLineWidth(s.tailW)
        c.move(to: s.tail[0])
        if s.tail.count >= 4 { c.addCurve(to: s.tail[3], control1: s.tail[1], control2: s.tail[2]) }
        else { for p in s.tail.dropFirst() { c.addLine(to: p) } }
        c.strokePath()
        // koyu uç
        c.setFillColor(dark)
        let tip = s.tail[s.tail.count - 1]
        c.fillEllipse(in: CGRect(x: tip.x - s.tailW * 0.45, y: tip.y - s.tailW * 0.45, width: s.tailW * 0.9, height: s.tailW * 0.9))
    }

    private static func body(_ c: CGContext, _ s: Spec) {
        c.saveGState()
        c.translateBy(x: s.body.x, y: s.body.y); c.rotate(by: s.rot)
        let rx = s.rx * s.puff, ry = s.ry * s.puff
        c.setFillColor(base)
        c.fillEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
        // göğüs/karın beyazı
        c.setFillColor(light)
        c.fillEllipse(in: CGRect(x: rx * 0.1, y: -ry * 0.1, width: rx * 0.8, height: ry * 0.95))
        // sırt çizgileri
        c.setStrokeColor(dark); c.setLineWidth(0.9)
        for k in [-0.45, 0.0, 0.45] as [CGFloat] {
            c.move(to: CGPoint(x: rx * k - 0.4, y: -ry * 0.98)); c.addLine(to: CGPoint(x: rx * k + 0.2, y: -ry * 0.35)); c.strokePath()
        }
        c.restoreGState()
        if let h = s.haunch {
            c.setFillColor(base)
            c.fillEllipse(in: CGRect(x: h.x - 4.0, y: h.y - 3.4, width: 8.0, height: 6.6))
            c.setFillColor(light)
            c.fillEllipse(in: CGRect(x: h.x + 1.0, y: h.y + 1.8, width: 5.6, height: 1.9))
        }
    }

    private static func head(_ c: CGContext, _ s: Spec) {
        c.saveGState()
        c.translateBy(x: s.head.x, y: s.head.y); c.rotate(by: s.headRot)
        let r = s.headR
        // kulaklar
        let back: CGFloat = s.earsBack ? 0.9 : 0
        c.setFillColor(base)
        c.move(to: CGPoint(x: -r * 0.78, y: -r * 0.30)); c.addLine(to: CGPoint(x: -r * 0.66, y: -r * (1.55 - back))); c.addLine(to: CGPoint(x: -r * 0.02, y: -r * 0.78))
        c.fillPath()
        c.move(to: CGPoint(x: r * 0.10, y: -r * 0.78)); c.addLine(to: CGPoint(x: r * 0.66, y: -r * (1.58 - back))); c.addLine(to: CGPoint(x: r * 0.90, y: -r * 0.30))
        c.fillPath()
        c.setFillColor(pink)
        c.move(to: CGPoint(x: r * 0.26, y: -r * 0.84)); c.addLine(to: CGPoint(x: r * 0.62, y: -r * (1.28 - back * 0.6))); c.addLine(to: CGPoint(x: r * 0.74, y: -r * 0.46))
        c.fillPath()
        // kafa
        c.setFillColor(base)
        c.fillEllipse(in: CGRect(x: -r, y: -r * 0.92, width: r * 2, height: r * 1.84))
        // ağız-burun bölgesi
        c.setFillColor(light)
        c.fillEllipse(in: CGRect(x: r * 0.18, y: -r * 0.05, width: r * 0.86, height: r * 0.62))
        c.setFillColor(pink)
        c.fillEllipse(in: CGRect(x: r * 0.80, y: -r * 0.10, width: r * 0.26, height: r * 0.20))
        if s.mouthOpen > 0 {
            c.setFillColor(ink)
            c.fillEllipse(in: CGRect(x: r * 0.42, y: r * 0.18, width: r * 0.55, height: r * 0.6))
            c.setFillColor(pink)
            c.fillEllipse(in: CGRect(x: r * 0.50, y: r * 0.46, width: r * 0.38, height: r * 0.24))
        } else if s.tongue {
            c.setFillColor(pink)
            c.fillEllipse(in: CGRect(x: r * 0.55, y: r * 0.28, width: r * 0.34, height: r * 0.38))
        }
        // göz
        let ex = r * 0.38, ey = -r * 0.16
        switch s.eyes {
        case .open, .wide:
            let w: CGFloat = s.eyes == .wide ? r * 0.62 : r * 0.48
            let h: CGFloat = s.eyes == .wide ? r * 0.62 : r * 0.44
            c.setFillColor(eyeGreen); c.fillEllipse(in: CGRect(x: ex - w / 2, y: ey - h / 2, width: w, height: h))
            c.setFillColor(ink); c.fillEllipse(in: CGRect(x: ex + w * 0.05, y: ey - h * 0.42, width: w * 0.34, height: h * 0.84))
        case .closed:
            c.setStrokeColor(ink); c.setLineWidth(0.8)
            c.move(to: CGPoint(x: ex - r * 0.26, y: ey)); c.addQuadCurve(to: CGPoint(x: ex + r * 0.26, y: ey), control: CGPoint(x: ex, y: ey + r * 0.22)); c.strokePath()
        case .happy:
            c.setStrokeColor(ink); c.setLineWidth(0.8)
            c.move(to: CGPoint(x: ex - r * 0.26, y: ey + r * 0.08)); c.addQuadCurve(to: CGPoint(x: ex + r * 0.26, y: ey + r * 0.08), control: CGPoint(x: ex, y: ey - r * 0.36)); c.strokePath()
        }
        c.restoreGState()
    }

    private static func zz(_ c: CGContext) {
        c.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.92, blue: 1, alpha: 0.95)); c.setLineWidth(0.7)
        func z(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat) {
            c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x + k, y: y)); c.addLine(to: CGPoint(x: x, y: y + k)); c.addLine(to: CGPoint(x: x + k, y: y + k)); c.strokePath()
        }
        z(21.6, 8.4, 2.2); z(24.2, 4.4, 2.8)
    }

    /// Kalp (tıklama tepkisi).
    static func heartImage(scale: Int) -> CGImage? {
        OfficeVectorArt.render(8, 8, scale: scale) { c in
            c.setFillColor(CGColor(srgbRed: 0.93, green: 0.25, blue: 0.36, alpha: 1))
            c.move(to: CGPoint(x: 4, y: 7.2))
            c.addCurve(to: CGPoint(x: 0.4, y: 2.6), control1: CGPoint(x: 1.4, y: 5.6), control2: CGPoint(x: 0.4, y: 4.2))
            c.addCurve(to: CGPoint(x: 4, y: 2.2), control1: CGPoint(x: 0.4, y: 0.6), control2: CGPoint(x: 3.0, y: 0.4))
            c.addCurve(to: CGPoint(x: 7.6, y: 2.6), control1: CGPoint(x: 5.0, y: 0.4), control2: CGPoint(x: 7.6, y: 0.6))
            c.addCurve(to: CGPoint(x: 4, y: 7.2), control1: CGPoint(x: 7.6, y: 4.2), control2: CGPoint(x: 6.6, y: 5.6))
            c.fillPath()
        }
    }
}

/// Sahne başına kare önbelleği (tembel). Piksel temada tek ölçek + nearest; vektörde 4x + doğrusal. Gece: karakterlerle aynı renk derecesi.
@MainActor
final class OfficeCatTextures {
    private var cache: [String: SKTexture] = [:]
    private(set) var theme: OfficeTheme
    var count: Int { cache.count }

    init(theme: OfficeTheme) { self.theme = theme }

    func texture(_ pose: OfficeCatPose, frame: Int, night: Bool) -> SKTexture {
        let f = frame % pose.frameCount
        let key = "\(pose.rawValue)|\(f)|\(night ? "n" : "d")"
        if let t = cache[key] { return t }
        let vec = theme == .vector
        guard var img = OfficeCatArt.image(pose, frame: f, scale: theme.textureScale, antialias: vec) else { return SKTexture() }
        if night { img = OfficeVectorCharacter.nightGrade(img) }
        let t = SKTexture(cgImage: img)
        t.filteringMode = vec ? .linear : .nearest
        cache[key] = t
        return t
    }

    func heart() -> SKTexture {
        if let t = cache["heart"] { return t }
        let vec = theme == .vector
        guard let img = OfficeCatArt.heartImage(scale: theme.textureScale) else { return SKTexture() }
        let t = SKTexture(cgImage: img)
        t.filteringMode = vec ? .linear : .nearest
        cache["heart"] = t
        return t
    }
}
