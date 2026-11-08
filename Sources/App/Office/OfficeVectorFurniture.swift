import CoreGraphics
import Foundation

// Vektör tema: mobilya katalogunun (Resources/Office/furniture manifest kimlikleri) modern karşılıkları. Mantıksal boyut/ayak izi katalogla
// AYNI (sprite = varlık genişliği × yüksekliği, y aşağı). Gölgeler sprite sınırı içinde kalır.

extension OfficeVectorArt {
    /// Vektör karşılığı olan mobilya kimlikleri (katalogdaki her kimlik).
    static let furnitureIDs: Set<String> = [
        "BIN", "BOOKSHELF", "CACTUS", "CLOCK", "COFFEE", "COFFEE_TABLE", "CUSHIONED_BENCH", "CUSHIONED_CHAIR_FRONT", "CUSHIONED_CHAIR_BACK",
        "CUSHIONED_CHAIR_SIDE", "DESK_FRONT", "DESK_SIDE", "DOUBLE_BOOKSHELF", "HANGING_PLANT", "LARGE_PAINTING", "LARGE_PLANT",
        "PC_FRONT_ON_1", "PC_FRONT_ON_2", "PC_FRONT_ON_3", "PC_FRONT_OFF", "PC_BACK", "PC_SIDE", "PLANT", "PLANT_2", "POT", "SMALL_PAINTING",
        "SMALL_PAINTING_2", "SMALL_TABLE_FRONT", "SMALL_TABLE_SIDE", "SOFA_FRONT", "SOFA_BACK", "SOFA_SIDE", "TABLE_FRONT", "WHITEBOARD",
        "WOODEN_BENCH", "WOODEN_CHAIR_FRONT", "WOODEN_CHAIR_BACK", "WOODEN_CHAIR_SIDE",
    ]

    /// Katalog varlığının vektör dokusu (boyut = varlık boyutu × 4).
    static func furniture(_ a: OfficeAsset) -> CGImage? {
        guard furnitureIDs.contains(a.id) else { return nil }
        return render(a.width, a.height) { _ = drawFurniture($0, a.id, CGFloat(a.width), CGFloat(a.height)) }
    }

    @discardableResult
    static func drawFurniture(_ c: CGContext, _ id: String, _ w: CGFloat, _ h: CGFloat) -> Bool {
        switch id {
        case "DESK_FRONT", "SMALL_TABLE_FRONT", "TABLE_FRONT": tableFront(c, w, h)
        case "DESK_SIDE", "SMALL_TABLE_SIDE": tableSide(c, w, h)
        case "COFFEE_TABLE": counter(c, w, h)
        case "COFFEE": espresso(c)
        case "CUSHIONED_BENCH": bench(c, wood: false)
        case "WOODEN_BENCH": bench(c, wood: true)
        case "CUSHIONED_CHAIR_FRONT": chair(c, h: h, view: .front, wood: false)
        case "CUSHIONED_CHAIR_BACK": chair(c, h: h, view: .back, wood: false)
        case "CUSHIONED_CHAIR_SIDE": chair(c, h: h, view: .side, wood: false)
        case "WOODEN_CHAIR_FRONT": chair(c, h: h, view: .front, wood: true)
        case "WOODEN_CHAIR_BACK": chair(c, h: h, view: .back, wood: true)
        case "WOODEN_CHAIR_SIDE": chair(c, h: h, view: .side, wood: true)
        case "SOFA_FRONT": sofa(c, w, h, back: false)
        case "SOFA_BACK": sofa(c, w, h, back: true)
        case "SOFA_SIDE": sofaSide(c, w, h)
        case "BOOKSHELF": shelf(c, w, h, rows: 2)
        case "DOUBLE_BOOKSHELF": shelf(c, w, h, rows: 4)
        case "CLOCK": clock(c)
        case "SMALL_PAINTING": painting(c, x: 2.6, y: 6, w: 10.8, h: 15, variant: 0)
        case "SMALL_PAINTING_2": painting(c, x: 2.6, y: 6, w: 10.8, h: 15, variant: 1)
        case "LARGE_PAINTING": painting(c, x: 2.4, y: 4, w: 27.2, h: 19, variant: 2)
        case "WHITEBOARD": whiteboard(c)
        case "PLANT": monstera(c, w, h, pot: 0xF3F0EA, scale: 1)
        case "PLANT_2": snakePlant(c, w, h)
        case "LARGE_PLANT": monstera(c, w, h, pot: 0xE9B79B, scale: 1.9)
        case "CACTUS": cactus(c, w, h)
        case "POT": pot(c)
        case "HANGING_PLANT": hangingPlant(c)
        case "BIN": bin(c)
        case "PC_FRONT_OFF": drawIMac(c, .silver, nil)
        case "PC_FRONT_ON_1": drawIMac(c, .silver, 0)
        case "PC_FRONT_ON_2": drawIMac(c, .silver, 1)
        case "PC_FRONT_ON_3": drawIMac(c, .silver, 2)
        case "PC_BACK": monitorBack(c)
        case "PC_SIDE": monitorSide(c)
        default: return false
        }
        return true
    }

    // MARK: Masalar

    /// Önden masa: açık meşe üst yüzey (üst-sol ışık), ince kenar şeridi, ince metal ayaklar, yumuşak gölge.
    private static func tableFront(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
        let top = h * 0.16, topEnd = h * 0.66, edgeEnd = h * 0.78
        c.vShadow(w / 2, h - 1.3, w * 0.48, 1.7, 0.22)
        for x in [2.6, w - 3.8] { c.vRR(x, edgeEnd - 0.5, 1.2, h - edgeEnd - 1.3, 0.5, fill: P.metal) }
        c.vRR(1.5, edgeEnd - 3.2, w - 3, 3.4, 0.9, fill: P.deskFront, stroke: 0xB7A98C, line: 0.3)
        c.vGradRR(0.8, top, w - 1.6, topEnd - top, 1.8, top: 0xFBF6EC, bottom: P.deskTop, stroke: 0xC9BBA0, line: 0.35)
        c.vLine(2.4, top + 0.7, w - 2.4, top + 0.7, 0xFFFFFF, width: 0.4, alpha: 0.7)
    }

    private static func tableSide(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
        c.vShadow(w / 2, h - 1.3, w * 0.45, 1.5, 0.2)
        for y in [h - 5.5, 4.5] { c.vRR(3.2, y, 1.2, 4, 0.5, fill: P.metal); c.vRR(w - 4.4, y, 1.2, 4, 0.5, fill: P.metal) }
        c.vGradRR(1.6, 2, w - 3.2, h - 8.4, 1.6, top: 0xFBF6EC, bottom: P.deskTop, stroke: 0xC9BBA0, line: 0.35)
        c.vRR(1.6, h - 7.2, w - 3.2, 2.6, 0.8, fill: P.deskFront, stroke: 0xB7A98C, line: 0.3)
    }

    /// Kahve tezgâhı: beyaz üst, koyu arduvaz dolap.
    private static func counter(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
        c.vShadow(w / 2, h - 1.2, w * 0.48, 1.6, 0.22)
        c.vGradRR(2, 21, w - 4, 8.6, 1.2, top: 0x66717F, bottom: 0x4C5663, stroke: 0x3C4550, line: 0.3)
        c.vLine(w / 2, 22.5, w / 2, 28.2, 0x3C4550, width: 0.35)
        c.vRR(w / 2 - 3.2, 24, 1.8, 0.6, 0.3, fill: 0xC4CBD6); c.vRR(w / 2 + 1.4, 24, 1.8, 0.6, 0.3, fill: 0xC4CBD6)
        c.vGradRR(0.8, 5.5, w - 1.6, 16.5, 2, top: 0xFFFFFF, bottom: 0xECE8DE, stroke: 0xC7C1B2, line: 0.35)
        c.vLine(2.4, 6.3, w - 2.4, 6.3, 0xFFFFFF, width: 0.4)
    }

    /// Modern espresso makinesi: gövde + tepsi + küçük ekran + fincan (buhar yok).
    private static func espresso(_ c: CGContext) {
        c.vShadow(8, 14.2, 6, 1.1, 0.25)
        c.vRR(3.4, 11.6, 9.4, 1.6, 0.7, fill: 0xC9CED6, stroke: 0x8D95A2, line: 0.25)
        c.vGradRR(2.6, 1.2, 10.8, 10.6, 1.6, top: 0x59626F, bottom: 0x2F353F, stroke: 0x23282F, line: 0.3)
        c.vRR(3.6, 2, 8.8, 1.6, 0.8, fill: 0xFFFFFF, alpha: 0.12)
        c.vRR(5, 3.6, 6, 2.4, 0.6, fill: 0x16301F); c.vRR(5.6, 4.2, 3.4, 0.5, 0.25, fill: 0x7ADBC3); c.vRR(5.6, 5.0, 2.2, 0.4, 0.2, fill: 0x7ADBC3, alpha: 0.7)
        c.vOval(10, 4.1, 1, 1, fill: 0xE98A78)
        c.vRR(6.9, 7, 2.2, 1.8, 0.4, fill: 0x9AA3B0)
        c.vRR(6.4, 9.4, 3.2, 2.3, 0.9, fill: 0xFFFFFF, stroke: 0xC7CCD4, line: 0.25)
    }

    // MARK: Oturma

    private static func bench(_ c: CGContext, wood: Bool) {
        c.vShadow(8, 14.4, 6.6, 1.2, 0.22)
        for x in [3.2, 11.8] { c.vRR(x, 10.6, 1, 4, 0.4, fill: P.metal) }
        if wood {
            c.vGradRR(1.6, 5.4, 12.8, 5.6, 1.4, top: 0xE2BE8D, bottom: 0xCDA46F, stroke: 0xA37C4C, line: 0.3)
            c.vLine(2.4, 8.2, 13.6, 8.2, 0xB88C59, width: 0.3)
        } else {
            c.vGradRR(1.4, 4.8, 13.2, 7, 2.6, top: 0x86CBD6, bottom: P.teal, stroke: 0x3F8E9C, line: 0.3)
            c.vLine(3.6, 6.2, 12.4, 6.2, 0xFFFFFF, width: 0.5, alpha: 0.45)
        }
    }

    enum ChairView { case front, back, side }

    /// Ofis sandalyesi: yuvarlak koltuk + sırt, renkli kumaş (mercan) ya da ahşap, tek ayak + yıldız taban. `h` 16 ya da 32 (ahşap).
    private static func chair(_ c: CGContext, h: CGFloat, view: ChairView, wood: Bool) {
        let o = h - 16   // yüksek (32) sandalyede içerik alta oturur
        let light: UInt32 = wood ? 0xE2BE8D : 0xF2A190, dark: UInt32 = wood ? 0xC49A66 : P.coral, line: UInt32 = wood ? 0xA37C4C : 0xC1604F
        c.vShadow(8, h - 1.4, 5.8, 1.2, 0.22)
        // tek ayak + yıldız taban
        c.vRR(7.4, o + 10.6, 1.2, 3.2, 0.4, fill: P.metal)
        c.vLine(4.2, o + 14.2, 11.8, o + 14.2, P.metal, width: 0.7)
        c.vOval(3.4, o + 13.7, 1.2, 1.1, fill: 0x555C68); c.vOval(11.4, o + 13.7, 1.2, 1.1, fill: 0x555C68)
        switch view {
        case .back:
            c.vRR(3, o + 7.6, 10, 3.8, 1.8, fill: dark, stroke: line, line: 0.3)
            c.vGradRR(3.2, o + 0.8, 9.6, 8.4, 3.4, top: light, bottom: dark, stroke: line, line: 0.3)
        case .front:
            c.vGradRR(3.4, o + 1, 9.2, 6.4, 3, top: light, bottom: dark, stroke: line, line: 0.3)
            c.vGradRR(2.6, o + 6.6, 10.8, 4.6, 2.2, top: light, bottom: dark, stroke: line, line: 0.3)
        case .side:
            c.vGradRR(2.8, o + 1, 3.4, 9, 1.7, top: light, bottom: dark, stroke: line, line: 0.3)
            c.vGradRR(3.4, o + 7.4, 9.6, 3.8, 1.9, top: light, bottom: dark, stroke: line, line: 0.3)
        }
    }

    private static func sofa(_ c: CGContext, _ w: CGFloat, _ h: CGFloat, back: Bool) {
        c.vShadow(w / 2, h - 1.2, w * 0.47, 1.3, 0.22)
        c.vGradRR(1, 1.2, w - 2, 9.6, 3.4, top: 0x93A3BC, bottom: 0x7889A5, stroke: 0x5F6F8A, line: 0.3)
        if !back {
            c.vGradRR(3.6, 7, w / 2 - 3.8, 6, 2.2, top: 0xA9B7CC, bottom: 0x8999B3, stroke: 0x6F7F9A, line: 0.3)
            c.vGradRR(w / 2 + 0.2, 7, w / 2 - 3.8, 6, 2.2, top: 0xA9B7CC, bottom: 0x8999B3, stroke: 0x6F7F9A, line: 0.3)
            for x in [0.6, w - 4.6] { c.vGradRR(x, 4.4, 4, 9, 2, top: 0x93A3BC, bottom: 0x7080A0, stroke: 0x5F6F8A, line: 0.3) }
        } else {
            c.vLine(w / 2, 2.6, w / 2, 9.6, 0x6F7F9A, width: 0.35)
            c.vRR(1.4, 9.4, w - 2.8, 3.4, 1.6, fill: 0x7080A0, stroke: 0x5F6F8A, line: 0.3)
        }
    }

    private static func sofaSide(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
        c.vShadow(w / 2, h - 1.2, w * 0.42, 1.3, 0.22)
        c.vGradRR(1.4, 2, 4.6, h - 5, 2.2, top: 0x93A3BC, bottom: 0x7889A5, stroke: 0x5F6F8A, line: 0.3)
        c.vGradRR(4.6, h * 0.4, w - 6, h * 0.42, 2.4, top: 0xA9B7CC, bottom: 0x8999B3, stroke: 0x6F7F9A, line: 0.3)
        c.vGradRR(4.2, h * 0.3, w - 5.6, 3.4, 1.7, top: 0x93A3BC, bottom: 0x7080A0, stroke: 0x5F6F8A, line: 0.3)
    }

    // MARK: Duvar öğeleri

    private static func wallShadow(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 1) {
        c.vRR(x + 0.7, y + 0.9, w, h, r, fill: 0x2A2118, alpha: 0.13)
    }

    /// Kitaplık: ahşap çerçeve, sıralı renkli kitap sırtları.
    private static func shelf(_ c: CGContext, _ w: CGFloat, _ h: CGFloat, rows: Int) {
        let top: CGFloat = rows > 2 ? 1.6 : 1.2, bottom = h - 0.6
        wallShadow(c, 0.8, top, w - 1.6, bottom - top, r: 1.2)
        c.vGradRR(0.6, top, w - 1.2, bottom - top, 1.2, top: 0xC99B6A, bottom: 0xB28254, stroke: 0x8C6339, line: 0.35)
        c.vRR(1.8, top + 1.2, w - 3.6, bottom - top - 2.4, 0.5, fill: 0xEFE3CE)
        let rowH = (bottom - top - 2.4) / CGFloat(rows)
        for r in 0..<rows {
            let y0 = top + 1.2 + CGFloat(r) * rowH, base = y0 + rowH
            var x: CGFloat = 2.3
            var i = r * 5
            while x < w - 2.6 {
                let bw = 1.2 + CGFloat((i * 3) % 4) * 0.35
                let bh = rowH * (0.55 + CGFloat((i * 5) % 4) * 0.12)
                if x + bw > w - 2.4 { break }
                if (i + r) % 7 == 3 { x += 1.6; i += 1; continue }
                c.vRR(x, base - 0.5 - bh, bw, bh, 0.3, fill: P.books[(i + r * 3) % P.books.count])
                c.vLine(x + 0.3, base - 0.5 - bh + 0.5, x + 0.3, base - 0.5 - bh + bh * 0.4, 0xFFFFFF, width: 0.2, alpha: 0.5)
                x += bw + 0.15; i += 1
            }
            c.vRR(1.8, base - 0.5, w - 3.6, 0.7, 0.2, fill: 0xB28254)
        }
    }

    private static func clock(_ c: CGContext) {
        c.vOval(3.1, 7.4, 11, 11, fill: 0x2A2118, alpha: 0.13)
        c.vOval(2.4, 6.4, 11.2, 11.2, fill: 0xFFFFFF, stroke: 0x4A4F57, line: 0.7)
        c.vOval(3.2, 7.2, 9.6, 9.6, stroke: 0xE4DFD4, line: 0.25)
        for i in 0..<12 {
            let a = CGFloat(i) * .pi / 6, r1: CGFloat = i % 3 == 0 ? 3.6 : 4.0, r2: CGFloat = 4.5
            c.vLine(8 + sin(a) * r1, 12 - cos(a) * r1, 8 + sin(a) * r2, 12 - cos(a) * r2, 0x4A4F57, width: i % 3 == 0 ? 0.45 : 0.25)
        }
        c.vLine(8, 12, 8 + sin(.pi / 3) * 3.0, 12 - cos(.pi / 3) * 3.0, 0x2F343B, width: 0.55)
        c.vLine(8, 12, 8 + sin(-.pi / 6) * 4.0, 12 - cos(-.pi / 6) * 4.0, 0x2F343B, width: 0.4)
        c.vOval(7.5, 11.5, 1, 1, fill: P.coral)
    }

    /// Çerçeveli soyut resim: geometrik renk blokları.
    private static func painting(_ c: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, variant: Int) {
        wallShadow(c, x, y, w, h, r: 0.8)
        c.vRR(x, y, w, h, 0.8, fill: 0xFFFFFF, stroke: 0xB9B1A2, line: 0.45)
        let m: CGFloat = w > 20 ? 2.2 : 1.4
        let ix = x + m, iy = y + m, iw = w - 2 * m, ih = h - 2 * m
        c.saveGState()
        c.addPath(CGPath(rect: CGRect(x: ix, y: iy, width: iw, height: ih), transform: nil)); c.clip()
        switch variant {
        case 0:
            c.setFillColor(c.vc(0xF4E9D6)); c.fill(CGRect(x: ix, y: iy, width: iw, height: ih))
            c.vOval(ix + iw * 0.15, iy + ih * 0.1, iw * 0.7, iw * 0.7, fill: P.coral)
            c.vRR(ix, iy + ih * 0.55, iw, ih * 0.45, 0, fill: P.teal)
            c.vRR(ix + iw * 0.5, iy + ih * 0.35, iw * 0.35, ih * 0.5, 0, fill: 0xF2C46D)
        case 1:
            c.setFillColor(c.vc(0xDCEBF2)); c.fill(CGRect(x: ix, y: iy, width: iw, height: ih))
            c.vPoly([CGPoint(x: ix, y: iy + ih), CGPoint(x: ix + iw * 0.6, y: iy + ih * 0.2), CGPoint(x: ix + iw, y: iy + ih)], fill: 0x7A8CC9)
            c.vOval(ix + iw * 0.55, iy + ih * 0.08, iw * 0.34, iw * 0.34, fill: 0xF2C46D)
            c.vPoly([CGPoint(x: ix, y: iy + ih), CGPoint(x: ix + iw * 0.3, y: iy + ih * 0.55), CGPoint(x: ix + iw * 0.7, y: iy + ih)], fill: 0x5FAFBE)
        default:
            c.setFillColor(c.vc(0xF7F2E8)); c.fill(CGRect(x: ix, y: iy, width: iw, height: ih))
            c.vRR(ix, iy, iw * 0.42, ih * 0.62, 0, fill: P.teal)
            c.vRR(ix + iw * 0.42, iy, iw * 0.58, ih * 0.38, 0, fill: 0xF2C46D)
            c.vOval(ix + iw * 0.52, iy + ih * 0.3, ih * 0.5, ih * 0.5, fill: P.coral)
            c.vRR(ix, iy + ih * 0.62, iw * 0.42, ih * 0.38, 0, fill: 0x2F3A4A)
            c.vRR(ix + iw * 0.8, iy + ih * 0.5, iw * 0.2, ih * 0.5, 0, fill: 0x8FB996)
        }
        c.restoreGState()
    }

    /// Modern beyaz tahta: ince alüminyum çerçeve, renkli notlar ve soluk bir şema. Yazı alanı (5,12,22×9) sahne katmanıyla örtülür.
    private static func whiteboard(_ c: CGContext) {
        wallShadow(c, 1.6, 3.4, 28.8, 21.4, r: 1.2)
        c.vGradRR(1.6, 3.4, 28.8, 21.4, 1.2, top: 0xE3E7EC, bottom: 0xC5CBD3, stroke: 0x98A1AE, line: 0.35)
        c.vRR(2.6, 4.4, 26.8, 19.4, 0.5, fill: 0xFAFBFC)
        c.vRR(2.6, 4.4, 26.8, 1.2, 0.5, fill: 0xFFFFFF)
        // yapışkan notlar
        c.vRR(4, 5.8, 5, 4.4, 0.4, fill: 0xFCE38A); c.vRR(11, 5.8, 5, 4.4, 0.4, fill: 0xA8E6CF); c.vRR(18, 6.2, 5, 4.4, 0.4, fill: 0xF9B8C9)
        for (x, hex) in [(4.8, 0xC9A93A), (11.8, 0x62B898), (18.8, 0xD98BA3)] as [(CGFloat, UInt32)] {
            c.vLine(x, 7.2, x + 3.4, 7.2, UInt32(hex), width: 0.3, alpha: 0.7); c.vLine(x, 8.4, x + 2.2, 8.4, UInt32(hex), width: 0.3, alpha: 0.7)
        }
        c.vRR(24.4, 5.6, 3.2, 3.2, 1.6, stroke: P.teal, line: 0.5)
        // soluk şema (yazma animasyonunun altında)
        c.vLine(5, 14, 16, 14, 0xD5DCE6, width: 0.6); c.vLine(5, 17, 12, 17, 0xD5DCE6, width: 0.6)
        c.vRR(18, 13, 8, 6, 1.2, stroke: 0xD5DCE6, line: 0.6)
        // tepsi + kalemler
        c.vRR(6, 23.8, 20, 1.6, 0.7, fill: 0xB9C0CA)
        c.vRR(9, 22.6, 3.4, 1.2, 0.5, fill: 0x3B7BFF); c.vRR(13.4, 22.6, 3.4, 1.2, 0.5, fill: 0xE86A5F); c.vRR(17.8, 22.6, 3.4, 1.2, 0.5, fill: 0x3FBF5F)
    }

    // MARK: Bitkiler

    private static func leaf(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, angle: CGFloat, hex: UInt32) {
        c.saveGState()
        c.translateBy(x: cx, y: cy); c.rotate(by: angle)
        c.vOval(-rx, -ry, rx * 2, ry * 2, fill: hex, stroke: 0x2F7048, line: 0.25)
        c.vLine(0, -ry * 0.8, 0, ry * 0.8, 0xBFE8CB, width: 0.3, alpha: 0.7)
        c.vLine(0, -ry * 0.1, rx * 0.6, -ry * 0.5, 0xBFE8CB, width: 0.2, alpha: 0.5)
        c.vLine(0, ry * 0.2, -rx * 0.6, -ry * 0.2, 0xBFE8CB, width: 0.2, alpha: 0.5)
        c.restoreGState()
    }

    private static func pot(_ c: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, hex: UInt32) {
        c.vGradRR(x, y, w, h, 1.4, top: hex, bottom: hex == 0xF3F0EA ? 0xDDD8CE : 0xC9886A, stroke: 0x9E8F7D, line: 0.3)
        c.vRR(x - 0.5, y, w + 1, 1.8, 0.8, fill: hex, stroke: 0x9E8F7D, line: 0.3)
    }

    /// Monstera: seramik saksı, geniş damarlı yapraklar. `scale` 1: 16x32; 1.9: 32x48.
    private static func monstera(_ c: CGContext, _ w: CGFloat, _ h: CGFloat, pot hex: UInt32, scale s: CGFloat) {
        let cx = w / 2
        c.vShadow(cx, h - 1.3, 5.6 * s, 1.2 * s, 0.22)
        let potH = 8.6 * s, potW = 7.4 * s
        let potY = h - 1.6 * s - potH
        let leaves: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, UInt32)] = [
            (-2.6, -4.5, 2.3, 3.5, -0.6, 0x3E8F5A), (2.8, -5.2, 2.3, 3.6, 0.55, 0x4FA36B), (0, -9, 2.6, 3.9, 0.05, 0x5DB57A),
            (-3.6, -9.5, 2.0, 3.2, -0.9, 0x4FA36B), (3.8, -10, 2.0, 3.2, 0.9, 0x3E8F5A), (0.2, -4.2, 2.2, 3.1, 0.25, 0x6CBE7F),
        ]
        for l in leaves { leaf(c, cx + l.0 * s, potY + l.1 * s * 0.9 - 1 * s, l.2 * s, l.3 * s, angle: l.4, hex: l.5) }
        pot(c, x: cx - potW / 2, y: potY, w: potW, h: potH, hex: hex)
    }

    /// Kılıç yapraklı bitki (sansevieria), terakota saksı.
    private static func snakePlant(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
        c.vShadow(8, h - 1.3, 5.4, 1.2, 0.22)
        let baseY: CGFloat = h - 10
        let blades: [(CGFloat, CGFloat, UInt32)] = [(-4, 15, 0x3E8F5A), (4.2, 13, 0x4FA36B), (-1.6, 18, 0x5DB57A), (1.6, 16, 0x3E8F5A), (0, 20, 0x4FA36B)]
        for (dx, hh, hex) in blades {
            let x = 8 + dx * 0.55
            c.vPoly([CGPoint(x: x - 1.5, y: baseY), CGPoint(x: x + dx * 0.25, y: baseY - hh), CGPoint(x: x + 1.5, y: baseY)], fill: hex, stroke: 0x2F7048, line: 0.25)
            c.vLine(x, baseY, x + dx * 0.25, baseY - hh + 2, 0xD9F0B0, width: 0.3, alpha: 0.6)
        }
        pot(c, x: 4.4, y: baseY - 0.4, w: 7.2, h: 8.6, hex: 0xE0956F)
    }

    private static func cactus(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
        c.vShadow(8, h - 1.3, 4.6, 1, 0.22)
        c.vRR(5.8, 9, 4.6, 14, 2.3, fill: 0x5DB57A, stroke: 0x2F7048, line: 0.3)
        c.vRR(2.8, 12, 3.2, 1.8, 0.9, fill: 0x5DB57A, stroke: 0x2F7048, line: 0.25); c.vRR(2.8, 8.4, 1.8, 5.4, 0.9, fill: 0x5DB57A, stroke: 0x2F7048, line: 0.25)
        c.vRR(10.2, 14, 3.2, 1.8, 0.9, fill: 0x5DB57A, stroke: 0x2F7048, line: 0.25); c.vRR(11.6, 10.4, 1.8, 5.4, 0.9, fill: 0x5DB57A, stroke: 0x2F7048, line: 0.25)
        c.vLine(8.1, 10, 8.1, 22, 0xBFE8CB, width: 0.3, alpha: 0.6)
        c.vOval(7.1, 7.6, 2, 2, fill: 0xF28FB1)
        pot(c, x: 4.6, y: 22.2, w: 6.8, h: 7.4, hex: 0xE0956F)
    }

    private static func pot(_ c: CGContext) {
        c.vShadow(8, 14.4, 5, 1, 0.22)
        pot(c, x: 4.4, y: 6, w: 7.2, h: 8.2, hex: 0xE0956F)
        c.vOval(5, 6.2, 6, 1.6, fill: 0x5A4332)
    }

    private static func hangingPlant(_ c: CGContext) {
        c.vLine(8, 0, 8, 3.4, 0x8A7A66, width: 0.3)
        c.vGradRR(5, 3.2, 6, 4.4, 1.6, top: 0xF3F0EA, bottom: 0xDDD8CE, stroke: 0x9E8F7D, line: 0.3)
        for (dx, len) in [(-3.0, 13.0), (-1.0, 17.0), (1.4, 14.0), (3.2, 10.0)] as [(CGFloat, CGFloat)] {
            c.vLine(8 + dx * 0.5, 7, 8 + dx, 7 + len, 0x4FA36B, width: 0.7)
            for k in 0..<3 { leaf(c, 8 + dx * (0.6 + 0.2 * CGFloat(k)), 9 + len * (0.3 + 0.3 * CGFloat(k)), 1.1, 1.7, angle: dx > 0 ? 0.6 : -0.6, hex: k % 2 == 0 ? 0x5DB57A : 0x3E8F5A) }
        }
    }

    private static func bin(_ c: CGContext) {
        c.vShadow(8, 14.4, 5.4, 1, 0.22)
        c.vGradRR(4.2, 4.6, 7.6, 9.6, 1.2, top: 0xB8BFC9, bottom: 0x8C94A1, stroke: 0x6F7783, line: 0.3)
        c.vOval(4, 3.6, 8, 2.4, fill: 0xD3D8DF, stroke: 0x6F7783, line: 0.3)
        c.vOval(4.9, 4.1, 6.2, 1.4, fill: 0x4A4F57)
        for x in [6.4, 8, 9.6] as [CGFloat] { c.vLine(x, 7.2, x, 12.4, 0x6F7783, width: 0.3, alpha: 0.7) }
    }

    private static func monitorBack(_ c: CGContext) {
        c.vShadow(8, 21.8, 7, 1.5, 0.17)
        c.vRR(4.8, 16.2, 6.4, 1.4, 0.7, fill: 0xBCC2CB, stroke: 0x6B7280, line: 0.25)
        c.vRR(7, 12.6, 2, 4.2, 0.4, fill: 0xBCC2CB)
        c.vGradRR(1, 0.8, 14, 12.8, 1.5, top: 0xE9ECF1, bottom: 0xD2D7DE, stroke: 0x9AA1AD, line: 0.35)
        c.vOval(6.6, 5.2, 2.8, 2.8, fill: 0xFFFFFF, alpha: 0.7)
    }

    private static func monitorSide(_ c: CGContext) {
        c.vShadow(8, 21.8, 5, 1.3, 0.17)
        c.vRR(4.8, 16.2, 6.4, 1.4, 0.7, fill: 0xBCC2CB, stroke: 0x6B7280, line: 0.25)
        c.vRR(7.2, 12.6, 1.8, 4.2, 0.4, fill: 0xBCC2CB)
        c.vGradRR(6.4, 0.8, 3.4, 12.8, 1.2, top: 0xFBFBFD, bottom: 0xE0E4EA, stroke: 0x9AA1AD, line: 0.35)
    }
}
