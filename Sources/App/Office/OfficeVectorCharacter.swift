import CoreGraphics
import Foundation

// Ofis vektör teması: parametrik karakter. Piksel sheet (char_N.png) yerine CoreGraphics ile mantıksal 24x32 (16 genişlik figür + 4'er birim
// kenar boşluğu; 4x = 96x128 px) tuvalde çizilir; y AŞAĞI. Kare dizinleri sheet sözleşmesiyle aynı (0-2 yürüme, 3-4 yazma, 5-6 okuma),
// 7+ vektöre özel ek pozlar. Sol bakış = sağın yatay yansıması (düğüm xScale -1 yapar). Kıyafet rengi, aksesuar (model + rol) ve
// kapüşon/yelek/kravat/önlük gövdeye pişirilir: ek düğüm yok. Işık yönü sol-üst: hafif beyaz kenar parıltısı (gece okunurluğu).

enum OfficeVectorCharacter {
    static let canvasW = 24
    static let canvasH = 32
    /// Figürün sol kenarının tuvaldeki başlangıcı (mantıksal birim).
    static let padX: CGFloat = 4
    static let frameCount = 18

    enum HairStyle: String, CaseIterable, Sendable { case short, bun, curly, long, afro, beanie }
    enum Prop: String, Sendable { case none, cleaner, carrier }

    struct Look: Sendable {
        var skin: UInt32
        var hair: UInt32
        var style: HairStyle
        var pants: UInt32
        var shoe: UInt32
        /// Bere (beanie) rengi; diğer stillerde kullanılmaz.
        var cap: UInt32
    }

    /// Altı ten tonu (açıktan koyuya).
    static let skinTones: [UInt32] = [0xF8DCC6, 0xEFC29E, 0xD9A074, 0xB87A52, 0x8D5A3A, 0x5E3A26]

    /// Temel görünümler (OfficeAppearance.characterIndex 0…5): Sonnet 0, yedek/yardımcı 1, Opus 2, bilinmeyen 3, Haiku 4, Fable 5.
    static let looks: [Look] = [
        Look(skin: skinTones[1], hair: 0x3A2A22, style: .short, pants: 0x394868, shoe: 0xF6F6F8, cap: 0),
        Look(skin: skinTones[0], hair: 0xB5533A, style: .bun, pants: 0x4A4F5C, shoe: 0xF6F6F8, cap: 0),
        Look(skin: skinTones[4], hair: 0x1C181B, style: .curly, pants: 0x4B4034, shoe: 0xF6F6F8, cap: 0),
        Look(skin: skinTones[2], hair: 0xE0B35E, style: .long, pants: 0x2F3A4F, shoe: 0xF6F6F8, cap: 0),
        Look(skin: skinTones[3], hair: 0x3B2723, style: .afro, pants: 0x3F5A4A, shoe: 0xF6F6F8, cap: 0),
        Look(skin: skinTones[5], hair: 0x2A2A30, style: .beanie, pants: 0x4A3F5F, shoe: 0xF6F6F8, cap: 0x2F8F9D),
    ]

    struct Spec: Hashable, Sendable {
        var look: Int
        var shirt: UInt32
        var hoodie = false
        var model = "none"
        var role = "none"
        var prop = Prop.none

        var key: String { String(format: "%d-%06X-%@-%@-%@-%@", look, shirt, hoodie ? "h" : "n", model, role, prop.rawValue) }
    }

    static func hex(_ c: OfficeRGB) -> UInt32 {
        func b(_ x: Double) -> UInt32 { UInt32((min(1, max(0, x)) * 255).rounded()) }
        return b(c.r) << 16 | b(c.g) << 8 | b(c.b)
    }

    /// Görünüm → parametre seti (model aksesuarı yöneticide, rol aksesuarı alt ajanda).
    static func spec(for a: OfficeAppearance) -> Spec {
        let look = min(max(a.characterIndex, 0), looks.count - 1)
        var s = Spec(look: look, shirt: hex(a.tint))
        s.hoodie = a.role?.hoodie ?? false
        s.role = a.role?.accessory.rawValue ?? "none"
        s.model = OfficeVectorCharacter.accessoryName(a.accessory)
        s.prop = a.prop
        return s
    }

    static func accessoryName(_ a: OfficeAccessory) -> String {
        switch a {
        case .none: "none"
        case .crown: "crown"
        case .cap: "cap"
        case .star: "star"
        case .sprout: "sprout"
        }
    }

    /// Model → temel görünüm (OfficeAppearance ile aynı eşleme).
    static func spec(look: Int, shirt: UInt32 = 0xF2F2F4) -> Spec { Spec(look: look, shirt: shirt) }

    // MARK: Pozlar

    enum PoseKind: Equatable, Sendable {
        case stand, walk(Int), type(Int), read(Int), board(Int), raise(Int), yawn, sleep, coffee(Int), carry(Int)
    }

    /// 0-2 yürüme (0,1,2: 1 = ayakta), 3-4 yazma, 5-6 okuma, 7-8 tahtada yazma, 9-10 el kaldırma, 11 esneme, 12 uyuklama,
    /// 13-14 kahve (fincan elde / ağızda), 15-17 koli taşıma (yürüme 0,1,2).
    static func kind(frame i: Int) -> PoseKind {
        switch i {
        case 0: .walk(-1)
        case 1: .stand
        case 2: .walk(1)
        case 3, 4: .type(i - 3)
        case 5, 6: .read(i - 5)
        case 7, 8: .board(i - 7)
        case 9, 10: .raise(i - 9)
        case 11: .yawn
        case 12: .sleep
        case 13, 14: .coffee(i - 13)
        case 15, 16, 17: .carry(i - 16)
        default: .stand
        }
    }

    /// Her kare için baş/gövde zıplaması (mantıksal birim, +aşağı): web aksesuar bağlama için.
    static func bob(frame i: Int) -> CGFloat {
        switch kind(frame: i) {
        case .walk(let p), .carry(let p): p == 0 ? 0 : 0.45
        case .sleep: 0.9
        default: 0
        }
    }

    enum Facing { case front, back, side }

    static func facing(_ d: OfficeCharacterSheet.Direction) -> Facing {
        switch d {
        case .down: .front
        case .up: .back
        case .left, .right: .side
        }
    }

    enum Mode { case color, mask, accessories }

    // MARK: Renk yardımcıları

    static func shade(_ hex: UInt32, _ f: CGFloat) -> UInt32 {
        func ch(_ s: UInt32) -> UInt32 { UInt32(min(255, max(0, (CGFloat((hex >> s) & 0xFF) * f).rounded()))) }
        return ch(16) << 16 | ch(8) << 8 | ch(0)
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> UInt32 {
        func ch(_ s: UInt32) -> UInt32 {
            let x = CGFloat((a >> s) & 0xFF), y = CGFloat((b >> s) & 0xFF)
            return UInt32(min(255, max(0, (x + (y - x) * t).rounded())))
        }
        return ch(16) << 16 | ch(8) << 8 | ch(0)
    }

    // MARK: Kare üretimi

    /// 4x görüntü (96x128). `.left` = `.right` karesinin yatay yansıması.
    static func image(spec: Spec, direction: OfficeCharacterSheet.Direction, frame: Int, mode: Mode = .color) -> CGImage? {
        let frame = min(max(frame, 0), frameCount - 1)
        return OfficeVectorArt.render(canvasW, canvasH) { c in
            if direction == .left { c.translateBy(x: CGFloat(canvasW), y: 0); c.scaleBy(x: -1, y: 1) }
            c.translateBy(x: padX, y: 0)
            drawFigure(c, spec: spec, facing: facing(direction), kind: kind(frame: frame), mode: mode)
        }
    }

    /// Gece derecelendirmesi: sahne gece çarpanı (`OfficeLightParams.duskFactor`) karakterleri de karartır; renkler önceden bu çarpanın
    /// (0.8 üssü) tersiyle açılır, böylece karakterler lambalı odada doygun ve okunur kalır (premultiplied alfa korunur).
    static func nightGrade(_ img: CGImage) -> CGImage {
        guard var px = OfficePixels(cgImage: img) else { return img }
        let k = OfficeLightParams.duskFactor.map { pow(1 / $0, 0.8) }
        var i = 0
        while i < px.data.count {
            let a = Double(px.data[i + 3])
            if a > 0 { for ch in 0..<3 { px.data[i + ch] = UInt8(min(a, Double(px.data[i + ch]) * k[ch])) } }
            i += 4
        }
        return px.cgImage() ?? img
    }

    /// Sözleşme: look (0…5), yön, kare dizini → vektör kare (varsayılan nötr gömlek).
    static func frame(look: Int, direction: OfficeCharacterSheet.Direction, frameIndex: Int, spec: Spec? = nil) -> CGImage? {
        image(spec: spec ?? Spec(look: min(max(look, 0), looks.count - 1), shirt: 0x5B8DEF), direction: direction, frame: frameIndex)
    }

    // MARK: Çizim

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func drawFigure(_ c: CGContext, spec: Spec, facing f: Facing, kind: PoseKind, mode: Mode) {
        let look = looks[min(max(spec.look, 0), looks.count - 1)]
        let mask = mode == .mask
        let body = mode != .accessories
        let acc = mode != .mask
        func H(_ hex: UInt32, _ shirt: Bool = false) -> UInt32 { mask ? (shirt ? 0xFFFFFF : 0x000000) : hex }
        let vest = spec.role == "vest"
        let shirt = spec.shirt
        let under = vest ? 0xF2EBD8 : shirt            // yelek altı: açık gömlek
        let shirtDk = shade(under, 0.62)
        let skin = look.skin
        let skinDk = shade(skin, 0.66)
        let side = f == .side

        var bob: CGFloat = 0
        var seated = false
        switch kind {
        case .walk(let p), .carry(let p): bob = p == 0 ? 0 : 0.45
        case .sleep: bob = 0.9; seated = true
        case .type, .read, .coffee: seated = true
        default: break
        }
        _ = seated

        // Bacaklar (kalça → ayak) + ayakkabı
        func leg(_ hip: CGPoint, _ foot: CGPoint, shoeW: CGFloat = 3.9, shoeShift: CGFloat = 0) {
            c.setLineCap(.round); c.setLineJoin(.round)
            c.setStrokeColor(c.vc(H(shade(look.pants, 0.55)))); c.setLineWidth(3.5)
            c.move(to: hip); c.addLine(to: CGPoint(x: foot.x, y: foot.y - 1)); c.strokePath()
            c.setStrokeColor(c.vc(H(look.pants))); c.setLineWidth(2.85)
            c.move(to: hip); c.addLine(to: CGPoint(x: foot.x, y: foot.y - 1)); c.strokePath()
            c.vRR(foot.x - shoeW / 2 + shoeShift, foot.y - 2.0, shoeW, 2.5, 1.2, fill: H(look.shoe), stroke: H(shade(look.shoe, 0.55)), line: 0.36)
        }
        func arm(_ pts: [CGPoint], sleeve: UInt32? = nil, hand: Bool = true) {
            guard pts.count >= 2 else { return }
            let col = sleeve ?? under
            c.setLineCap(.round); c.setLineJoin(.round)
            let path = CGMutablePath()
            path.move(to: pts[0]); for p in pts.dropFirst() { path.addLine(to: p) }
            c.addPath(path); c.setStrokeColor(c.vc(H(shade(col, 0.58), true))); c.setLineWidth(3.1); c.strokePath()
            c.addPath(path); c.setStrokeColor(c.vc(H(col, true))); c.setLineWidth(2.45); c.strokePath()
            if hand, let e = pts.last { c.vOval(e.x - 1.25, e.y - 1.25, 2.5, 2.5, fill: H(skin), stroke: H(skinDk), line: 0.32) }
        }
        func shifted(_ pts: [CGPoint]) -> [CGPoint] { pts.map { CGPoint(x: $0.x, y: $0.y + bob) } }
        func mirror(_ pts: [CGPoint]) -> [CGPoint] { pts.map { CGPoint(x: 16 - $0.x, y: $0.y) } }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

        // MARK: Kollar (poz tablosu)
        var armL: [CGPoint] = [], armR: [CGPoint] = []      // ön/arka görünüm: ekran solu / sağı
        var armFar: [CGPoint] = [], armNear: [CGPoint] = [] // yan görünüm
        var mug: CGPoint?                                    // fincan konumu (sol üst)
        var book = false, box = false
        var mouthOpen = false, eyesClosed = false
        var headTilt: CGFloat = 0, headDX: CGFloat = 0, headDY: CGFloat = 0
        switch kind {
        case .stand:
            armL = [pt(4.6, 17.6), pt(3.5, 21), pt(3.3, 24)]
            armFar = [pt(8.2, 17.6), pt(8.3, 21), pt(8.0, 24)]
            armNear = [pt(8.4, 17.6), pt(8.6, 21), pt(8.8, 24)]
        case .walk(let p):
            let pf = CGFloat(p)
            armL = [pt(4.6, 17.6), pt(3.6, 21), pt(3.4, 24 - 0.8 * pf)]
            armR = mirror([pt(4.6, 17.6), pt(3.6, 21), pt(3.4, 24 + 0.8 * pf)])
            armFar = [pt(8.2, 17.6), pt(8.4 + pf * 1.4, 21), pt(8.2 + pf * 2.6, 23.6)]
            armNear = [pt(8.4, 17.6), pt(8.6 - pf * 1.4, 21), pt(8.8 - pf * 2.6, 23.8)]
        case .type(let i):
            let up: CGFloat = 1.3
            // Arkadan görünümde yalnızca dirsek görünür: dirsekler de dönüşümlü kalkar (yazma hareketi okunur).
            armL = [pt(4.6, 17.6), pt(3.2, 21.4 - (i == 0 ? 1.1 : 0)), pt(5.8, 20.4 - (i == 0 ? up : 0))]
            armR = mirror([pt(4.6, 17.6), pt(3.2, 21.4 - (i == 1 ? 1.1 : 0)), pt(5.8, 20.4 - (i == 1 ? up : 0))])
            armFar = [pt(8.2, 17.6), pt(9.2, 21.2), pt(11.4, 20.2 - (i == 1 ? up : 0))]
            armNear = [pt(8.4, 17.6), pt(9.0, 21.4), pt(11.8, 20.6 - (i == 0 ? up : 0))]
        case .read(let i):
            let dy = CGFloat(i) * 0.5
            armL = [pt(4.6, 17.6), pt(3.4, 21.6), pt(6.4, 19.4 - dy)]
            armR = mirror(armL)
            armFar = [pt(8.2, 17.6), pt(9.2, 21.2), pt(11.0, 19.0 - dy)]
            armNear = [pt(8.4, 17.6), pt(9.2, 21.4), pt(11.6, 19.6 - dy)]
            book = true
        case .board(let i):
            let fi = CGFloat(i)
            armL = [pt(4.6, 17.6), pt(3.5, 21), pt(3.3, 24)]
            armR = [pt(11.4, 17.6), pt(13.9, 14.6), pt(12.6 + (i == 0 ? 1.4 : -0.6), 10.8 - 0.8 * fi)]
            armFar = [pt(8.2, 17.6), pt(8.3, 21), pt(8.0, 24)]
            armNear = [pt(8.4, 17.6), pt(11.4, 14.8), pt(12.8 + (i == 0 ? 1.0 : -0.6), 11.0 - 0.8 * fi)]
        case .raise(let i):
            armL = [pt(4.6, 17.6), pt(3.5, 21), pt(3.3, 24)]
            armR = [pt(11.4, 17.6), pt(13.7, 13.6), pt(13.5 + (i == 0 ? 0.9 : -0.9), 8.6)]
            armFar = [pt(8.2, 17.6), pt(8.3, 21), pt(8.0, 24)]
            armNear = [pt(8.4, 17.6), pt(11.2, 14.0), pt(12.2 + (i == 0 ? 0.8 : -0.8), 8.6)]
        case .yawn:
            armL = [pt(4.6, 17.6), pt(2.4, 14.6), pt(3.2, 10.6)]
            armR = mirror(armL)
            armFar = [pt(8.2, 17.6), pt(10.4, 15.2), pt(9.2, 11.2)]
            armNear = [pt(8.4, 17.6), pt(11.0, 15.4), pt(10.2, 11.0)]
            mouthOpen = true; eyesClosed = true
        case .sleep:
            armL = [pt(4.6, 17.6), pt(3.2, 21.4), pt(5.8, 21.0)]
            armR = mirror(armL)
            armFar = [pt(8.2, 17.6), pt(9.2, 21.2), pt(11.4, 21.2)]
            armNear = [pt(8.4, 17.6), pt(9.0, 21.4), pt(11.8, 21.6)]
            eyesClosed = true; headTilt = 0.2; headDX = 0.5; headDY = 1.0
        case .coffee(let i):
            armL = [pt(4.6, 17.6), pt(3.2, 21.4), pt(5.8, 20.4)]
            armR = i == 0 ? [pt(11.4, 17.6), pt(13.4, 21.2), pt(12.2, 19.2)] : [pt(11.4, 17.6), pt(13.2, 18.4), pt(10.6, 14.6)]
            armFar = [pt(8.2, 17.6), pt(9.2, 21.2), pt(10.8, 20.4)]
            armNear = i == 0 ? [pt(8.4, 17.6), pt(10.4, 20.4), pt(11.8, 18.8)] : [pt(8.4, 17.6), pt(11.0, 17.4), pt(11.6, 14.8)]
            mug = i == 0 ? pt(12.8, 15.8) : pt(11.8, 12.0)
            if side { mug = i == 0 ? pt(10.8, 15.8) : pt(11.0, 12.4) }
            else if i == 1 { mug = pt(9.8, 11.6) }
        case .carry:
            armL = [pt(4.6, 17.6), pt(3.4, 21.6), pt(5.0, 22.8)]
            armR = mirror(armL)
            armFar = [pt(8.2, 17.6), pt(9.6, 21.2), pt(11.4, 22.4)]
            armNear = [pt(8.4, 17.6), pt(10.0, 21.6), pt(11.6, 22.8)]
            box = true
        }

        // MARK: Bacaklar
        if body {
            var lift: (l: CGFloat, r: CGFloat) = (0, 0)
            var sw: CGFloat = 0
            switch kind {
            case .walk(let p), .carry(let p):
                lift = (p == -1 ? 1.4 : 0, p == 1 ? 1.4 : 0); sw = CGFloat(p)
            default: break
            }
            if side {
                // arka bacak (daha koyu), sonra ön bacak
                leg(pt(7.6, 23.2 + bob), pt(7.6 - 2.7 * sw, 30.0 - (sw == 0 ? 0 : 0.9)), shoeW: 4.3, shoeShift: 0.5)
                leg(pt(8.6, 23.2 + bob), pt(8.6 + 2.7 * sw, 30.0), shoeW: 4.3, shoeShift: 0.5)
            } else {
                leg(pt(6.4, 23.2 + bob), pt(6.2, 30.0 - lift.l))
                leg(pt(9.6, 23.2 + bob), pt(9.8, 30.0 - lift.r))
            }
        }

        // MARK: Uzun saç (arka katman: gövdenin arkasında)
        let hcx: CGFloat = side ? 8.5 : 8
        let hcy: CGFloat = 11.0 + bob
        let rx: CGFloat = side ? 5.2 : 5.5, ry: CGFloat = 5.2
        func headSpace(_ d: () -> Void) {
            c.saveGState()
            c.translateBy(x: 8, y: 15.6 + bob); c.rotate(by: headTilt); c.translateBy(x: -8 + headDX, y: -(15.6 + bob) + headDY)
            d()
            c.restoreGState()
        }

        if body && look.style == .long {
            headSpace {
                if f == .front { for sx in [hcx - rx - 0.9, hcx + rx - 1.9] { c.vRR(sx, hcy - 0.5, 2.8, 9.6, 1.4, fill: H(look.hair), stroke: H(shade(look.hair, 0.55)), line: 0.36) } }
                if side { c.vRR(hcx - rx - 0.9, hcy - 1.0, 4.0, 9.8, 1.8, fill: H(look.hair), stroke: H(shade(look.hair, 0.55)), line: 0.36) }
            }
        }

        // MARK: Gövde
        if body {
            if side { arm(shifted(armFar), sleeve: mix(under, 0x000000, 0.18)) }
            if box && f == .back { c.vRR(2.9, 17.8 + bob, 10.2, 6.8, 1, fill: H(0xC8964B), stroke: H(0x7A5426), line: 0.38) }
            let tw: CGFloat = side ? 6.0 : 7.8, tx: CGFloat = side ? 5.2 : 4.1
            c.vRR(tx, 15.6 + bob, tw, 9.6, side ? 2.4 : 2.9, fill: H(under, true), stroke: H(shirtDk, true), line: 0.38)
            if f == .front { c.vOval(6.6, 15.2 + bob, 2.8, 1.8, fill: H(skin), stroke: H(skinDk), line: 0.3) }   // yaka boşluğu
        }

        // MARK: Gövde süsleri (kapüşon, yelek, kravat, etiket, önlük, binoküler)
        let role = spec.role
        func chest() {
            if spec.hoodie && body {
                let dk = shade(shirt, 0.74)
                switch f {
                case .front:
                    c.vOval(3.4, 14.2 + bob, 9.2, 4.4, fill: H(dk, true), stroke: H(shade(shirt, 0.5), true), line: 0.36)   // kapüşon yakası
                    c.vOval(5.6, 15.0 + bob, 4.8, 2.6, fill: H(skin), stroke: H(skinDk), line: 0.3)
                    c.vRR(5.2, 21.2 + bob, 5.6, 2.8, 1.2, fill: H(dk, true), stroke: H(shade(shirt, 0.5), true), line: 0.3)  // kanguru cep
                    c.vLine(7.2, 17.6 + bob, 7.0, 20.4 + bob, H(0xF2F2F6), width: 0.5); c.vLine(8.8, 17.6 + bob, 9.0, 20.4 + bob, H(0xF2F2F6), width: 0.5)
                case .back:
                    c.vRR(4.4, 14.4 + bob, 7.2, 7.4, 3.4, fill: H(dk, true), stroke: H(shade(shirt, 0.5), true), line: 0.36)   // sırttaki kapüşon
                    c.vLine(8, 15.4 + bob, 8, 21 + bob, H(shade(shirt, 0.55), true), width: 0.35)
                case .side:
                    c.vOval(3.6, 14.6 + bob, 5.4, 6.8, fill: H(dk, true), stroke: H(shade(shirt, 0.5), true), line: 0.36)
                }
            }
            guard acc || body else { return }
            switch role {
            case "vest":
                let vc = shirt
                switch f {
                case .front:
                    c.vRR(4.4, 16.0 + bob, 3.0, 8.8, 1.2, fill: H(vc, true), stroke: H(shade(vc, 0.6), true), line: 0.34)
                    c.vRR(8.6, 16.0 + bob, 3.0, 8.8, 1.2, fill: H(vc, true), stroke: H(shade(vc, 0.6), true), line: 0.34)
                    c.vRR(4.4, 20.4 + bob, 7.2, 1.1, 0.4, fill: H(0xFFF8C4), alpha: 0.95)
                case .back:
                    c.vRR(4.4, 16.0 + bob, 7.2, 8.8, 1.4, fill: H(vc, true), stroke: H(shade(vc, 0.6), true), line: 0.34)
                    c.vRR(4.4, 20.4 + bob, 7.2, 1.1, 0.4, fill: H(0xFFF8C4), alpha: 0.95)
                    c.vLine(5.8, 16.4 + bob, 10.2, 20.4 + bob, H(0xFFF8C4), width: 0.7); c.vLine(10.2, 16.4 + bob, 5.8, 20.4 + bob, H(0xFFF8C4), width: 0.7)
                case .side:
                    c.vRR(5.4, 16.0 + bob, 5.6, 8.8, 1.2, fill: H(vc, true), stroke: H(shade(vc, 0.6), true), line: 0.34)
                    c.vRR(5.4, 20.4 + bob, 5.6, 1.1, 0.4, fill: H(0xFFF8C4), alpha: 0.95)
                }
            case "tie":
                let navy: UInt32 = 0x2B3A67
                switch f {
                case .front:
                    c.vPoly([pt(6.0, 15.6 + bob), pt(8, 17.2 + bob), pt(7.2, 18.0 + bob)], fill: H(0xFFFFFF), stroke: H(0xB8BDC8), line: 0.28)
                    c.vPoly([pt(10.0, 15.6 + bob), pt(8, 17.2 + bob), pt(8.8, 18.0 + bob)], fill: H(0xFFFFFF), stroke: H(0xB8BDC8), line: 0.28)
                    c.vPoly([pt(7.2, 17.4 + bob), pt(8.8, 17.4 + bob), pt(9.3, 22.6 + bob), pt(8, 24 + bob), pt(6.7, 22.6 + bob)], fill: H(navy), stroke: H(shade(navy, 0.6)), line: 0.3)
                case .back: c.vRR(5.8, 15.6 + bob, 4.4, 1.4, 0.7, fill: H(0xFFFFFF), stroke: H(0xB8BDC8), line: 0.28)
                case .side: c.vRR(9.4, 17.0 + bob, 1.6, 6.4, 0.6, fill: H(navy), stroke: H(shade(navy, 0.6)), line: 0.3)
                }
            case "tag":
                c.vLine(8, 15.8 + bob, side ? 10.0 : 10.4, 18.4 + bob, H(0x555B66), width: 0.4)
                if f != .back { c.vRR(side ? 9.4 : 9.4, 18.2 + bob, 3.2, 2.6, 0.5, fill: H(0xF4F6FA), stroke: H(0x6A7080), line: 0.3); c.vRR(9.4, 18.2 + bob, 3.2, 0.9, 0.4, fill: H(shirt)) }
            case "binoculars":
                c.vLine(6.2, 15.8 + bob, 8, 20.2 + bob, H(0x333640), width: 0.45); c.vLine(9.8, 15.8 + bob, 8, 20.2 + bob, H(0x333640), width: 0.45)
                if f != .back {
                    c.vRR(5.8, 19.4 + bob, 2.4, 3.4, 1.1, fill: H(0x4A4F5C), stroke: H(0x23252D), line: 0.3)
                    c.vRR(7.8, 19.4 + bob, 2.4, 3.4, 1.1, fill: H(0x4A4F5C), stroke: H(0x23252D), line: 0.3)
                    c.vOval(6.2, 22.0 + bob, 1.6, 1.0, fill: H(0x9BD4FF)); c.vOval(8.2, 22.0 + bob, 1.6, 1.0, fill: H(0x9BD4FF))
                }
            default: break
            }
            if spec.prop == .cleaner && body {
                c.vRR(5.2, 18.0 + bob, 5.6, 7.0, 1.4, fill: H(0xF4F8FF), stroke: H(0x9DB4D8), line: 0.34)
                c.vRR(6.2, 16.4 + bob, 3.6, 2.0, 0.8, fill: H(0xF4F8FF), stroke: H(0x9DB4D8), line: 0.3)
            }
        }
        if body { chest() } else if acc && (role == "vest" || role == "tie" || role == "tag" || role == "binoculars") { chest() }

        // MARK: Koli (önde)
        if body && box && f != .back {
            let bx: CGFloat = side ? 9.0 : 3.6, bw: CGFloat = side ? 5.4 : 8.8
            c.vRR(bx, 18.0 + bob, bw, 6.8, 1, fill: H(0xC8964B), stroke: H(0x7A5426), line: 0.38)
            c.vRR(bx, 20.6 + bob, bw, 1.0, 0.3, fill: H(0xE6C98A))
        }

        // MARK: Kollar
        if body {
            if side {
                arm(shifted(armNear))
            } else {
                // Arkadan görünümde masaya uzanan eller gövdenin önündedir: yalnızca üst kol (dirsek) görünür.
                var backHidden = false
                if f == .back { switch kind { case .type, .read, .sleep, .carry: backHidden = true; default: break } }
                var coffeeL = false
                if f == .back, case .coffee = kind { coffeeL = true }
                if backHidden || coffeeL { arm(shifted(Array(armL.prefix(2))), hand: false) } else { arm(shifted(armL)) }
                if backHidden { arm(shifted(Array(armR.prefix(2))), hand: false) } else { arm(shifted(armR)) }
            }
            if book, f != .back {
                let bx: CGFloat = side ? 10.4 : 5.2
                c.vRR(bx, 17.6 + bob, side ? 3.4 : 5.6, 3.6, 0.5, fill: H(0xB5651D), stroke: H(0x5E3512), line: 0.34)
                c.vRR(bx + 0.5, 18.1 + bob, side ? 2.4 : 4.6, 2.6, 0.3, fill: H(0xF6EBD0))
            }
        }
        if let m = mug, body || acc {
            let o = m.y + bob
            c.vRR(m.x, o, 2.9, 3.0, 0.9, fill: H(0xFAFAFA), stroke: H(0x9A9AA6), line: 0.3)
            c.vOval(m.x + 0.3, o + 0.2, 2.3, 0.9, fill: H(0x6B3E1E))
            c.setStrokeColor(c.vc(H(0x9A9AA6))); c.setLineWidth(0.4)
            c.addArc(center: pt(m.x + 3.0, o + 1.6), radius: 0.9, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false); c.strokePath()
        }

        // MARK: Hand items (sağ yan)
        func handItem() {
            guard acc else { return }
            let ox: CGFloat = side ? 12.2 : 13.2
            let y = 0.0 + bob
            switch role {
            case "book":
                c.vRR(ox + 0.4, 18.6 + y, 3.8, 5.0, 0.7, fill: H(0xB5651D), stroke: H(0x5E3512), line: 0.34)
                c.vRR(ox + 1.1, 19.2 + y, 2.6, 3.8, 0.4, fill: H(0xF6EBD0))
                c.vLine(ox + 1.2, 18.8 + y, ox + 1.2, 23.4 + y, H(0x7A4210), width: 0.4)
            case "clipboard":
                c.vRR(ox + 0.2, 17.6 + y, 4.2, 6.0, 0.7, fill: H(0x6B5538), stroke: H(0x3E3020), line: 0.34)
                c.vRR(ox + 0.8, 18.8 + y, 3.0, 4.4, 0.4, fill: H(0xFAFAF6))
                for k in 0..<3 { c.vLine(ox + 1.2, 19.8 + y + CGFloat(k) * 1.1, ox + 3.4, 19.8 + y + CGFloat(k) * 1.1, H(0x8892A6), width: 0.3) }
                c.vRR(ox + 1.4, 17.2 + y, 2.4, 1.1, 0.5, fill: H(0xC0C4CC), stroke: H(0x6A7080), line: 0.28)
            case "compass":
                c.vOval(ox + 0.4, 18.4 + y, 4.4, 4.4, fill: H(0xF4F4EE), stroke: H(0x1F6F6B), line: 0.5)
                c.vPoly([pt(ox + 2.6, 19.0 + y), pt(ox + 3.2, 20.6 + y), pt(ox + 2.0, 20.6 + y)], fill: H(0xE0262B))
                c.vPoly([pt(ox + 2.6, 22.2 + y), pt(ox + 3.2, 20.6 + y), pt(ox + 2.0, 20.6 + y)], fill: H(0x2F6FDE))
            case "magnifier":
                c.vLine(ox + 0.6, 24.2 + y, ox + 2.4, 20.6 + y, H(0x333844), width: 0.8)
                c.vOval(ox + 1.4, 16.8 + y, 4.2, 4.2, fill: H(0xBFE6FF), alpha: 0.8, stroke: H(0x333844), line: 0.55)
                c.vOval(ox + 2.2, 17.5 + y, 1.1, 0.8, fill: H(0xFFFFFF), alpha: 0.8)
            case "ruler":
                c.vRR(ox + 1.0, 15.8 + y, 2.1, 9.4, 0.5, fill: H(0xE8C55A), stroke: H(0x8A6A18), line: 0.32)
                for k in 0..<4 { c.vLine(ox + 1.0, 17.0 + y + CGFloat(k) * 1.9, ox + 2.0, 17.0 + y + CGFloat(k) * 1.9, H(0x7A5A10), width: 0.3) }
            default: break
            }
        }
        if mode != .mask { handItem() }

        // MARK: Baş
        func head() {
            func hairPath(_ region: CGPath, grow: CGFloat = 0.5) -> CGPath {
                let e = CGPath(ellipseIn: CGRect(x: hcx - rx - grow, y: hcy - ry - grow - 0.2, width: 2 * (rx + grow), height: 2 * (ry + grow) + 0.2), transform: nil)
                return e.intersection(region)
            }
            func poly(_ pts: [CGPoint]) -> CGPath { let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath(); return p }
            func fillHair(_ p: CGPath, color: UInt32, outline: Bool = true) {
                c.vPath(p, fill: H(color), stroke: outline ? H(shade(color, 0.55)) : nil, line: 0.38)
            }
            let hair = look.hair
            let hairStroke = shade(hair, 0.55)

            // Saç arka katmanı
            if body {
                switch look.style {
                case .afro:
                    c.vOval(hcx - 7.0, hcy - 7.4, 14.0, 13.6, fill: H(hair), stroke: H(hairStroke), line: 0.4)
                case .bun:
                    let bx = side ? hcx - 3.4 : hcx
                    c.vOval(bx - 2.3, hcy - ry - 2.8, 4.6, 4.4, fill: H(hair), stroke: H(hairStroke), line: 0.38)
                case .curly:
                    for k in 0..<7 {
                        let a = CGFloat.pi * (1.12 + 0.76 * CGFloat(k) / 6)
                        c.vOval(hcx + cos(a) * (rx + 0.4) - 2.1, hcy + sin(a) * (ry + 0.3) - 2.1 + 0.2, 4.2, 4.2, fill: H(hair), stroke: H(hairStroke), line: 0.38)
                    }
                default: break
                }
            }
            // Kulaklar
            if body && f == .front {
                c.vOval(hcx - rx - 0.9, hcy + 0.2, 2.2, 2.6, fill: H(skin), stroke: H(skinDk), line: 0.3)
                c.vOval(hcx + rx - 1.3, hcy + 0.2, 2.2, 2.6, fill: H(skin), stroke: H(skinDk), line: 0.3)
            }
            // Kafa
            if body { c.vOval(hcx - rx, hcy - ry, 2 * rx, 2 * ry, fill: H(skin), stroke: H(skinDk), line: 0.4) }
            if body && side {
                c.vOval(hcx + rx - 0.8, hcy + 1.0, 1.7, 1.6, fill: H(skin), stroke: H(skinDk), line: 0.3)       // burun
                c.vOval(hcx - 1.6, hcy + 0.4, 2.4, 2.8, fill: H(skin), stroke: H(skinDk), line: 0.3)            // kulak
            }
            // Saç ön katmanı
            if body {
                switch look.style {
                case .beanie:
                    let capCol = look.cap
                    let top = f == .back ? hcy + 0.6 : hcy - 1.0
                    let dome = hairPath(poly([pt(-5, -5), pt(21, -5), pt(21, top), pt(-5, top)]), grow: 0.8)
                    c.vPath(dome, fill: H(capCol), stroke: H(shade(capCol, 0.55)), line: 0.4)
                    let band = hairPath(poly([pt(-5, top - 1.7), pt(21, top - 1.7), pt(21, top + 0.1), pt(-5, top + 0.1)]), grow: 0.9)
                    c.vPath(band, fill: H(mix(capCol, 0xFFFFFF, 0.38)), stroke: H(shade(capCol, 0.55)), line: 0.34)
                default:
                    var region: CGPath
                    switch f {
                    case .front:
                        let p = CGMutablePath()
                        p.move(to: pt(-5, -5)); p.addLine(to: pt(21, -5)); p.addLine(to: pt(hcx + rx + 1, hcy + 2.2))
                        p.addLine(to: pt(hcx + rx - 0.9, hcy - 0.3))
                        p.addQuadCurve(to: pt(hcx - rx + 1.5, hcy - 0.2), control: pt(hcx + 0.6, hcy - 3.6))
                        p.addLine(to: pt(hcx - rx - 1, hcy + 2.2)); p.closeSubpath()
                        region = p
                        if look.style == .afro { region = poly([pt(-5, -5), pt(21, -5), pt(21, hcy - 1.6), pt(-5, hcy - 1.6)]) }
                    case .back:
                        region = poly([pt(-5, -5), pt(21, -5), pt(21, hcy + 3.3), pt(-5, hcy + 3.3)])
                    case .side:
                        let p = CGMutablePath()
                        p.move(to: pt(-5, -5)); p.addLine(to: pt(21, -5)); p.addLine(to: pt(21, hcy - 1.0))
                        p.addLine(to: pt(hcx + 2.4, hcy - 1.3))
                        p.addQuadCurve(to: pt(hcx - 0.6, hcy + 0.2), control: pt(hcx + 0.4, hcy - 1.6))
                        p.addLine(to: pt(hcx - 0.9, hcy + 3.0)); p.addLine(to: pt(-5, hcy + 3.0)); p.closeSubpath()
                        region = p
                    }
                    fillHair(hairPath(region), color: hair)
                    if look.style == .afro && f == .back { c.vOval(hcx - 7.0, hcy - 7.4, 14.0, 13.6, fill: H(hair), stroke: H(hairStroke), line: 0.4) }
                    if look.style == .long && f == .back { c.vRR(hcx - rx - 0.6, hcy - 1.5, 2 * rx + 1.2, 11.6, 3.4, fill: H(hair), stroke: H(hairStroke), line: 0.38) }
                    if look.style == .curly && f == .back { for k in 0..<5 { c.vOval(hcx - 5.4 + CGFloat(k) * 2.3, hcy + 1.2 + CGFloat(k % 2) * 0.6, 3.6, 3.6, fill: H(hair), stroke: H(hairStroke), line: 0.36) } }
                }
            }
            // Yüz
            if body {
                let ink: UInt32 = 0x2B2B38
                if f == .front {
                    if eyesClosed {
                        for ex in [hcx - 2.3, hcx + 2.3] { c.vLine(ex - 0.9, hcy + 1.0, ex + 0.9, hcy + 1.0, H(ink), width: 0.5) }
                    } else {
                        c.vOval(hcx - 3.2, hcy - 0.1, 1.7, 2.4, fill: H(ink)); c.vOval(hcx + 1.5, hcy - 0.1, 1.7, 2.4, fill: H(ink))
                        c.vOval(hcx - 2.8, hcy + 0.2, 0.6, 0.7, fill: H(0xFFFFFF)); c.vOval(hcx + 1.9, hcy + 0.2, 0.6, 0.7, fill: H(0xFFFFFF))
                    }
                    c.vOval(hcx - 4.5, hcy + 2.4, 1.9, 1.1, fill: H(0xE98A78), alpha: 0.4); c.vOval(hcx + 2.6, hcy + 2.4, 1.9, 1.1, fill: H(0xE98A78), alpha: 0.4)
                    if mouthOpen { c.vOval(hcx - 0.8, hcy + 2.6, 1.6, 1.9, fill: H(0x7A2E2E)) }
                    else {
                        c.setStrokeColor(c.vc(H(0x8A4A44))); c.setLineWidth(0.4); c.setLineCap(.round)
                        c.move(to: pt(hcx - 0.9, hcy + 3.0)); c.addQuadCurve(to: pt(hcx + 0.9, hcy + 3.0), control: pt(hcx, hcy + 3.7)); c.strokePath()
                    }
                } else if f == .side {
                    if eyesClosed { c.vLine(hcx + rx - 3.0, hcy + 1.1, hcx + rx - 1.4, hcy + 1.1, H(ink), width: 0.5) }
                    else { c.vOval(hcx + rx - 3.2, hcy + 0.1, 1.5, 2.1, fill: H(ink)); c.vOval(hcx + rx - 2.9, hcy + 0.4, 0.55, 0.65, fill: H(0xFFFFFF)) }
                    c.vOval(hcx + rx - 4.4, hcy + 2.4, 1.8, 1.1, fill: H(0xE98A78), alpha: 0.4)
                    if mouthOpen { c.vOval(hcx + rx - 2.2, hcy + 2.6, 1.3, 1.7, fill: H(0x7A2E2E)) }
                    else { c.vLine(hcx + rx - 2.4, hcy + 3.2, hcx + rx - 1.2, hcy + 3.2, H(0x8A4A44), width: 0.4) }
                }
            }
            guard acc else { return }
            // Yüz aksesuarları
            if role == "glasses" {
                let g: UInt32 = 0x23262E
                if f == .front {
                    c.vOval(hcx - 4.1, hcy - 0.7, 3.6, 3.6, fill: H(0xCDE8FF), alpha: 0.4, stroke: H(g), line: 0.5)
                    c.vOval(hcx + 0.5, hcy - 0.7, 3.6, 3.6, fill: H(0xCDE8FF), alpha: 0.4, stroke: H(g), line: 0.5)
                    c.vLine(hcx - 0.5, hcy + 1.0, hcx + 0.5, hcy + 1.0, H(g), width: 0.5)
                } else if f == .side {
                    c.vOval(hcx + rx - 4.6, hcy - 0.8, 3.6, 3.6, fill: H(0xCDE8FF), alpha: 0.4, stroke: H(g), line: 0.5)
                    c.vLine(hcx + rx - 4.6, hcy + 1.0, hcx - 1.2, hcy + 0.6, H(g), width: 0.5)
                } else {
                    c.vLine(hcx - rx, hcy + 0.6, hcx + rx, hcy + 0.6, H(g), width: 0.45)
                }
            }
            if role == "headphones" {
                let band: UInt32 = 0x2C2F3A, cup: UInt32 = 0xB04CE8
                c.setStrokeColor(c.vc(H(band))); c.setLineWidth(1.0); c.setLineCap(.round)
                c.addArc(center: pt(hcx, hcy + 0.4), radius: rx + 0.5, startAngle: .pi * 1.06, endAngle: .pi * 1.94, clockwise: false); c.strokePath()
                if side {
                    c.vRR(hcx - 2.4, hcy - 0.6, 2.8, 4.0, 1.3, fill: H(cup), stroke: H(shade(cup, 0.5)), line: 0.34)
                } else {
                    c.vRR(hcx - rx - 1.1, hcy - 0.8, 2.4, 4.2, 1.1, fill: H(cup), stroke: H(shade(cup, 0.5)), line: 0.34)
                    c.vRR(hcx + rx - 1.3, hcy - 0.8, 2.4, 4.2, 1.1, fill: H(cup), stroke: H(shade(cup, 0.5)), line: 0.34)
                }
            }
            // Model/gösterge aksesuarı (baş üstü)
            let topOffset: CGFloat
            switch look.style {
            case .afro: topOffset = 7.4
            case .curly: topOffset = 7.4
            case .bun: topOffset = 7.4
            case .beanie: topOffset = 6.2
            default: topOffset = 5.9
            }
            let topY = hcy - topOffset + 0.8
            let tx = side ? hcx - 0.4 : hcx
            var model = spec.model
            if spec.prop == .carrier { model = "hardhat" }
            switch model {
            case "crown":
                let w: CGFloat = side ? 2.6 : 3.4
                c.vPoly([pt(tx - w, topY + 0.4), pt(tx - w, topY - 2.6), pt(tx - w / 2, topY - 1.0), pt(tx, topY - 3.2), pt(tx + w / 2, topY - 1.0), pt(tx + w, topY - 2.6), pt(tx + w, topY + 0.4)],
                        fill: H(0xFFD23F), stroke: H(0xB8860B), line: 0.4)
                c.vRR(tx - w, topY - 0.2, 2 * w, 0.9, 0.3, fill: H(0xE7A91E))
                if f != .back { c.vOval(tx - 0.55, topY - 1.4, 1.1, 1.1, fill: H(0xE0262B), stroke: H(0x8A1418), line: 0.2) }
            case "cap":
                let capCol: UInt32 = 0x2F6FDE
                let dome = hairPath(poly([pt(-5, -5), pt(21, -5), pt(21, hcy - 1.4), pt(-5, hcy - 1.4)]), grow: 0.75)
                c.vPath(dome, fill: H(capCol), stroke: H(shade(capCol, 0.55)), line: 0.4)
                c.vOval(tx - 1.2, hcy - 5.2, 2.2, 1.0, fill: H(0x7FB0FF), alpha: 0.55)
                if f == .front { c.vRR(hcx - 3.4, hcy - 2.1, 6.8, 1.5, 0.7, fill: H(0x1B4DA8), stroke: H(0x123778), line: 0.34) }
                if side { c.vRR(hcx + rx - 1.2, hcy - 2.1, 4.2, 1.4, 0.7, fill: H(0x1B4DA8), stroke: H(0x123778), line: 0.34) }
                if f == .back { c.vOval(tx - 0.6, hcy - ry - 0.6, 1.2, 1.2, fill: H(0x1B4DA8)) }
            case "hardhat":
                let hc: UInt32 = 0xF2A12A
                let dome = hairPath(poly([pt(-5, -5), pt(21, -5), pt(21, hcy - 1.2), pt(-5, hcy - 1.2)]), grow: 0.8)
                c.vPath(dome, fill: H(hc), stroke: H(shade(hc, 0.55)), line: 0.4)
                c.vRR(hcx - rx - 0.6, hcy - 1.9, 2 * rx + 1.2, 1.3, 0.6, fill: H(shade(hc, 0.85)), stroke: H(shade(hc, 0.55)), line: 0.34)
            case "star":
                let r: CGFloat = 2.5, cy = topY - 1.6
                var pts: [CGPoint] = []
                for k in 0..<10 {
                    let a = -CGFloat.pi / 2 + CGFloat(k) * .pi / 5
                    let rr = k % 2 == 0 ? r : r * 0.45
                    pts.append(pt(tx + cos(a) * rr, cy + sin(a) * rr))
                }
                c.vPoly(pts, fill: H(0xFFC400), stroke: H(0xD98200), line: 0.4)
            case "sprout":
                let g: UInt32 = 0x4CD964, d: UInt32 = 0x2E8B3D
                c.vLine(tx, topY + 0.6, tx, topY - 1.8, H(d), width: 0.7)
                c.saveGState(); c.translateBy(x: tx - 1.2, y: topY - 2.0); c.rotate(by: -0.5)
                c.vOval(-2.0, -1.1, 3.2, 2.1, fill: H(g), stroke: H(d), line: 0.32); c.restoreGState()
                c.saveGState(); c.translateBy(x: tx + 1.2, y: topY - 2.4); c.rotate(by: 0.5)
                c.vOval(-1.2, -1.1, 3.2, 2.1, fill: H(g), stroke: H(d), line: 0.32); c.restoreGState()
            default: break
            }
        }
        headSpace { head() }

        // Işık: sol-üst beyaz kenar parıltısı + sağ-alt hafif gölge (yalnızca renk modunda).
        if mode == .color {
            c.saveGState()
            c.setBlendMode(.sourceAtop)
            let sp = CGColorSpace(name: CGColorSpace.sRGB)!
            let lightG = CGGradient(colorsSpace: sp, colors: [c.vc(0xFFFFFF, 0.34), c.vc(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(lightG, start: pt(side ? 3.6 : 2.2, 0), end: pt(side ? 8.2 : 7.4, 0), options: [])
            let darkG = CGGradient(colorsSpace: sp, colors: [c.vc(0x0A1030, 0), c.vc(0x0A1030, 0.18)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(darkG, start: pt(8.6, 0), end: pt(14.2, 0), options: [])
            let topG = CGGradient(colorsSpace: sp, colors: [c.vc(0xFFFFFF, 0.14), c.vc(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(topG, start: pt(0, 2), end: pt(0, 9), options: [])
            c.restoreGState()
            c.saveGState()
            c.setBlendMode(.destinationOver)
            c.vShadow(8, 30.2, 6.4, 1.5, 0.26)
            c.restoreGState()
        }
    }
}
