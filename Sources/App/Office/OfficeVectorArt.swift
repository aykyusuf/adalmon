import CoreGraphics
import Foundation

// Ofis modern vektör teması: dokular CoreGraphics ile mantıksal birimde (16 pt/karo, y AŞAĞI, sol-üst başlangıç) çizilir, `scale`
// (4x) kat büyütülerek rasterleştirilir. Işık yönü sol-üst. Aynı çizim işlevleri SpriteKit dokularını, oda pişirmesini ve tarayıcıya
// giden PNG'leri üretir (tek doğruluk kaynağı).

/// Vektör tema paleti (hex). Sınırlı sıcak-nötr; vurgu: nane (duvar bandı), mercan (sandalye), turkuaz (bank).
enum OfficeVectorPalette {
    static let wall: UInt32 = 0xF4EFE6
    static let wallShade: UInt32 = 0xE6DECF
    static let wallEdge: UInt32 = 0xCFC4B1
    static let skirting: UInt32 = 0xD8CEBC
    static let accent: UInt32 = 0x9ADBC6
    static let accentDark: UInt32 = 0x6FBFA6
    static let sideWall: UInt32 = 0xE9E2D4
    static let floorBase: UInt32 = 0xDDBE92
    static let floorTones: [UInt32] = [0xDDBE92, 0xD9BA8D, 0xE1C398, 0xD5B68A]
    static let plankLine: UInt32 = 0xC2A073
    static let carpet: UInt32 = 0x8FA7C4
    static let carpetBorder: UInt32 = 0xDCE7F3
    static let carpetDot: UInt32 = 0x7C95B4
    static let deskTop: UInt32 = 0xF1E8D8
    static let deskFront: UInt32 = 0xD6C8AE
    static let metal: UInt32 = 0x8D95A2
    static let ink: UInt32 = 0x4A4F57
    static let teal: UInt32 = 0x5FAFBE
    static let coral: UInt32 = 0xE98A78
    static let sky: [UInt32] = [0x8FCBF2, 0xD7EFFF]
    static let nightSky: [UInt32] = [0x0E1A40, 0x2D468A]
    static let books: [UInt32] = [0xE98A78, 0x5FAFBE, 0xF2C46D, 0x8FB996, 0x7A8CC9, 0xD98BB0, 0xF4EFE6, 0x6B7A8F]
}

extension CGContext {
    func vc(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    func vPath(_ p: CGPath, fill: UInt32? = nil, alpha: CGFloat = 1, stroke: UInt32? = nil, line: CGFloat = 0.4, strokeAlpha: CGFloat = 1) {
        if let fill { setFillColor(vc(fill, alpha)); addPath(p); fillPath() }
        if let stroke { setStrokeColor(vc(stroke, strokeAlpha)); setLineWidth(line); addPath(p); strokePath() }
    }

    /// Yuvarlatılmış dikdörtgen; `line` > 0 ve `stroke` verilirse ince kenar çizgisi.
    func vRR(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, fill: UInt32? = nil, alpha: CGFloat = 1,
             stroke: UInt32? = nil, line: CGFloat = 0.35) {
        let rr = max(0, min(r, min(w, h) / 2))
        vPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: rr, cornerHeight: rr, transform: nil),
              fill: fill, alpha: alpha, stroke: stroke, line: line)
    }

    func vOval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, fill: UInt32? = nil, alpha: CGFloat = 1, stroke: UInt32? = nil, line: CGFloat = 0.35) {
        vPath(CGPath(ellipseIn: CGRect(x: x, y: y, width: w, height: h), transform: nil), fill: fill, alpha: alpha, stroke: stroke, line: line)
    }

    func vPoly(_ pts: [CGPoint], fill: UInt32? = nil, alpha: CGFloat = 1, stroke: UInt32? = nil, line: CGFloat = 0.35) {
        let p = CGMutablePath()
        p.addLines(between: pts); p.closeSubpath()
        vPath(p, fill: fill, alpha: alpha, stroke: stroke, line: line)
    }

    func vLine(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ hex: UInt32, width: CGFloat = 0.5, alpha: CGFloat = 1) {
        setStrokeColor(vc(hex, alpha)); setLineWidth(width); setLineCap(.round)
        move(to: CGPoint(x: x1, y: y1)); addLine(to: CGPoint(x: x2, y: y2)); strokePath()
    }

    /// Dikey degrade dolgu (yuvarlak köşeli dikdörtgen içinde).
    func vGradRR(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, top: UInt32, bottom: UInt32, stroke: UInt32? = nil, line: CGFloat = 0.35) {
        let rr = max(0, min(r, min(w, h) / 2))
        let p = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: rr, cornerHeight: rr, transform: nil)
        saveGState(); addPath(p); clip()
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [vc(top), vc(bottom)] as CFArray, locations: [0, 1])!
        drawLinearGradient(g, start: CGPoint(x: x, y: y), end: CGPoint(x: x, y: y + h), options: [])
        restoreGState()
        if let stroke { vPath(p, stroke: stroke, line: line) }
    }

    /// Yumuşak elips gölge (radyal): merkez `a`, kenar 0.
    func vShadow(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ a: CGFloat = 0.18, hex: UInt32 = 0x1A1A24) {
        saveGState()
        translateBy(x: cx, y: cy); scaleBy(x: rx, y: ry)
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [vc(hex, a), vc(hex, a * 0.55), vc(hex, 0)] as CFArray, locations: [0, 0.55, 1])!
        drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        restoreGState()
    }

    /// Radyal ışık (merkez renk+alfa → kenar saydam).
    func vGlow(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, hex: UInt32, alpha: CGFloat, falloff: CGFloat = 1.6) {
        saveGState()
        translateBy(x: cx, y: cy); scaleBy(x: rx, y: ry)
        var colors: [CGColor] = [], locs: [CGFloat] = []
        for i in 0...8 {
            let t = CGFloat(i) / 8
            colors.append(vc(hex, alpha * pow(1 - t, falloff))); locs.append(t)
        }
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locs)!
        drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        restoreGState()
    }
}

enum OfficeVectorArt {
    typealias P = OfficeVectorPalette
    static var scale: Int { OfficeTheme.vectorScale }

    /// Mantıksal `w`×`h` birimlik tuval (y aşağı), `scale` kat piksel; `draw` mantıksal birimde çizer.
    static func render(_ w: Int, _ h: Int, scale: Int = OfficeTheme.vectorScale, _ draw: (CGContext) -> Void) -> CGImage? {
        let pw = w * scale, ph = h * scale
        guard pw > 0, ph > 0, let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true); ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(ph)); ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        draw(ctx)
        return ctx.makeImage()
    }

    // MARK: Anahtarlar

    /// Piksel `OfficeArt` adlarından vektör karşılığı olanlar (bilgisayarlar, lamba, ışıklar). Diğerleri (rol aksesuarı, fincan, zzz, mop, koli)
    /// bu turda piksel kalır (karakterlerle birlikte sonraki turda çevrilir).
    static var artNames: [String] {
        var out: [String] = []
        for pc in OfficeArt.allComputers {
            out.append(OfficeArt.computerName(pc, frame: nil))
            for f in 0..<3 { out.append(OfficeArt.computerName(pc, frame: f)) }
        }
        return out + ["lamp"] + glowSpecs.map(\.name)
    }

    static func hasArt(_ name: String) -> Bool { artNames.contains(name) }

    static func art(_ name: String) -> CGImage? {
        if let g = glowSpecs.first(where: { $0.name == name }) { return glow(g) }
        if name == "lamp" { return render(8, 10) { drawLamp($0) } }
        for pc in OfficeArt.allComputers {
            if name == OfficeArt.computerName(pc, frame: nil) { return computer(pc, frame: nil) }
            for f in 0..<3 where name == OfficeArt.computerName(pc, frame: f) { return computer(pc, frame: f) }
        }
        return nil
    }

    /// Mantıksal boyut (sprite boyutu): bilgisayar 16x32, lamba 8x10; ışıklar `glowSpecs`.
    static func artSize(_ name: String) -> CGSize? {
        if let g = glowSpecs.first(where: { $0.name == name }) { return CGSize(width: g.logicalW, height: g.logicalH) }
        if name == "lamp" { return CGSize(width: 8, height: 10) }
        return hasArt(name) ? CGSize(width: 16, height: 32) : nil
    }

    // MARK: Işık dokuları

    struct GlowSpec: Sendable {
        var name: String
        /// Mantıksal (sahne birimi) boyut.
        var logicalW: Int
        var logicalH: Int
        var hex: UInt32
    }

    /// Yüksek çözünürlüklü pişirilmiş radyal gradyanlar (tepe alfa 1: sahnede sprite alfası ile kısılır).
    static let glowSpecs: [GlowSpec] = [
        GlowSpec(name: "vglow_bulb", logicalW: 64, logicalH: 64, hex: 0xFFD67A),
        GlowSpec(name: "vglow_pool", logicalW: 40, logicalH: 24, hex: 0xFFD27A),
        GlowSpec(name: "vglow_screen", logicalW: 24, logicalH: 16, hex: 0x9CCBFF),
        GlowSpec(name: "vglow_moon", logicalW: 24, logicalH: 40, hex: 0x8FB2FF),
    ]

    static func glow(_ g: GlowSpec) -> CGImage? {
        render(g.logicalW, g.logicalH, scale: 4) {
            $0.vGlow(CGFloat(g.logicalW) / 2, CGFloat(g.logicalH) / 2, CGFloat(g.logicalW) / 2, CGFloat(g.logicalH) / 2, hex: g.hex, alpha: 1, falloff: g.name == "vglow_bulb" ? 2.0 : 1.5)
        }
    }

    // MARK: Lamba, kapı

    /// Masa lambası: yuvarlak taban, esnek kol, koni başlık (sıcak).
    static func drawLamp(_ c: CGContext) {
        c.vShadow(4, 9.2, 3.2, 0.8, 0.25)
        c.vRR(1.6, 8, 4.8, 1.4, 0.7, fill: 0x3C424D)
        c.setStrokeColor(c.vc(0x3C424D)); c.setLineWidth(0.6); c.setLineCap(.round)
        c.move(to: CGPoint(x: 4, y: 8)); c.addQuadCurve(to: CGPoint(x: 5.3, y: 3.6), control: CGPoint(x: 2.6, y: 5.4)); c.strokePath()
        c.vPoly([CGPoint(x: 3.6, y: 1.2), CGPoint(x: 7.4, y: 2.2), CGPoint(x: 6.6, y: 4.6), CGPoint(x: 4.2, y: 3.8)], fill: 0x4A515E)
        c.vOval(4.2, 3.6, 2.4, 1.0, fill: 0xFFE9A8)
    }

    /// 16x32 kapı: ceviz kasa + panel, pirinç kol, hafif gölge.
    static func door() -> CGImage? {
        render(16, 32) { c in
            c.vShadow(8, 31.4, 7, 1.2, 0.2)
            c.vRR(1, 2, 14, 30, 1.2, fill: 0x6B4A33, stroke: 0x47301F, line: 0.4)
            c.vGradRR(2.4, 3.4, 11.2, 28.4, 0.8, top: 0x9A6C48, bottom: 0x7E5336)
            c.vRR(4, 5.5, 8, 8.5, 0.8, stroke: 0x6B4A33, line: 0.35)
            c.vRR(4, 16.5, 8, 11.5, 0.8, stroke: 0x6B4A33, line: 0.35)
            c.vOval(10.6, 17.4, 1.6, 1.6, fill: 0xE8C066, stroke: 0xB48B3A, line: 0.25)
            c.vLine(2.6, 3.8, 2.6, 30, 0xC79A72, width: 0.3, alpha: 0.6)
        }
    }

    // MARK: Beyaz tahta "yazıyor" kareleri

    /// 22x9 mantıksal alan (tahta dokusunda x 5, y 12); piksel yolu ile aynı konum/boyut. Opak beyaz zemin + 3 aşamalı çizgiler.
    static func boardFrames() -> [CGImage] {
        let lines: [[(y: CGFloat, len: CGFloat, hex: UInt32)]] = [
            [(1.8, 10, 0x3B7BFF)],
            [(1.8, 17, 0x3B7BFF), (4.6, 8, 0x3B7BFF)],
            [(1.8, 17, 0x3B7BFF), (4.6, 13, 0x3B7BFF), (7.2, 6, 0xE86A5F)],
        ]
        return lines.compactMap { frame in
            render(22, 9) { c in
                c.setFillColor(c.vc(0xFAFBFC)); c.fill(CGRect(x: 0, y: 0, width: 22, height: 9))
                for l in frame { c.vLine(1.5, l.y, 1.5 + l.len, l.y, l.hex, width: 1.1) }
            }
        }
    }
    static let boardWriteSize = CGSize(width: 22, height: 9)
    static let boardWriteOrigin = CGPoint(x: 5, y: 12)

    // MARK: Bilgisayarlar (iMac / MacBook)

    private static let imacTints: [OfficeComputer.Color: (chin: UInt32, neck: UInt32)] = [
        .blue: (0x6F9BEF, 0x5C86D8), .green: (0x8FD18F, 0x6FBA7C), .pink: (0xF2A7BC, 0xDC8EA6), .silver: (0xDDE1E7, 0xBCC2CB),
    ]
    private static let macbookBodies: [OfficeComputer.Color: (body: UInt32, key: UInt32)] = [.silver: (0xD9DDE3, 0xAEB4BE), .gray: (0x80868F, 0x5B616B)]

    /// Ekran içeriği: yumuşak koyu tema, renkli "kod" satırları; kare 0…2 farklı satırlar, imleç 0-1 karelerinde görünür (yanıp söner).
    private static func screenContent(_ c: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, frame: Int?) {
        c.saveGState()
        let clip = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: 0.7, cornerHeight: 0.7, transform: nil)
        c.addPath(clip); c.clip()
        guard let frame else {
            c.setFillColor(c.vc(0x10151C)); c.fill(CGRect(x: x, y: y, width: w, height: h))
            c.vPoly([CGPoint(x: x + w * 0.1, y: y), CGPoint(x: x + w * 0.45, y: y), CGPoint(x: x + w * 0.2, y: y + h), CGPoint(x: x - w * 0.15, y: y + h)], fill: 0xFFFFFF, alpha: 0.07)
            c.restoreGState()
            return
        }
        c.setFillColor(c.vc(0x1B2433)); c.fill(CGRect(x: x, y: y, width: w, height: h))
        c.setFillColor(c.vc(0x232E41)); c.fill(CGRect(x: x, y: y, width: w, height: 0.9))
        let rows: [[(CGFloat, CGFloat, UInt32)]] = [
            [(0, 0.45, 0x7CD992), (0.5, 0.3, 0x6CA8FF)],
            [(0.12, 0.55, 0x6CA8FF), (0, 0.2, 0xF2C46D)],
            [(0.2, 0.4, 0xE98A9B), (0.2, 0.3, 0x7CD992)],
            [(0.12, 0.5, 0x7CD992), (0, 0.25, 0x6CA8FF)],
            [(0, 0.35, 0xF2C46D), (0.3, 0.3, 0xE98A9B)],
        ]
        let lineH = (h - 1.4) / 5.2
        let shown = [3, 4, 5][frame % 3]
        var lastEnd: CGFloat = x + 0.7, lastY = y + 0.7
        for i in 0..<shown {
            let ry = y + 0.8 + CGFloat(i) * lineH * 1.05
            var cx = x + 0.8
            for (indent, len, hex) in rows[(i + frame) % rows.count] {
                cx += indent * w * 0.5
                let lw = len * (w - 1.8) * 0.9
                c.vRR(cx, ry, lw, lineH * 0.55, lineH * 0.27, fill: hex, alpha: 0.95)
                cx += lw + 0.5
            }
            lastEnd = cx; lastY = ry
        }
        if frame != 2 { c.vRR(min(lastEnd, x + w - 1.6), lastY - 0.1, 0.9, lineH * 0.75, 0.2, fill: 0xE8EDF5) }
        c.vPoly([CGPoint(x: x + w * 0.6, y: y), CGPoint(x: x + w * 0.95, y: y), CGPoint(x: x + w * 0.65, y: y + h), CGPoint(x: x + w * 0.3, y: y + h)], fill: 0xFFFFFF, alpha: 0.05)
        c.restoreGState()
    }

    static func computer(_ pc: OfficeComputer, frame: Int?) -> CGImage? {
        render(16, 32) { c in
            if pc.kind == .imac { drawIMac(c, pc.color, frame) } else { drawMacBook(c, pc.color, frame) }
        }
    }

    /// iMac: ince gümüş/beyaz gövde, renkli çene, ayaklık, klavye + fare. 16x32.
    static func drawIMac(_ c: CGContext, _ color: OfficeComputer.Color, _ frame: Int?) {
        let t = imacTints[color] ?? imacTints[.silver]!
        c.vShadow(8, 21.8, 7.4, 1.6, 0.17)
        c.vShadow(8, 17.6, 4.2, 0.8, 0.2)
        // ayaklık + boyun
        c.vRR(4.8, 16.2, 6.4, 1.4, 0.7, fill: t.neck, stroke: 0x6B7280, line: 0.25)
        c.vGradRR(7, 12.6, 2, 4.2, 0.4, top: t.neck, bottom: t.neck)
        // gövde + ekran
        c.vGradRR(1, 0.8, 14, 12.8, 1.5, top: 0xFBFBFD, bottom: 0xE9ECF1, stroke: 0x9AA1AD, line: 0.35)
        c.vRR(2.1, 1.9, 11.8, 7.9, 0.7, fill: 0x0C1017)
        screenContent(c, x: 2.3, y: 2.1, w: 11.4, h: 7.5, frame: frame)
        c.vGradRR(1.05, 10.3, 13.9, 3.3, 1.3, top: t.chin, bottom: t.neck)
        c.vOval(7.35, 11.4, 1.3, 1.3, fill: 0xFFFFFF, alpha: 0.55)
        // klavye + fare
        c.vRR(1.4, 18.6, 10.4, 3.4, 0.9, fill: 0xF6F7FA, stroke: 0xA7ADB8, line: 0.3)
        for i in 0..<4 { c.vLine(2.6 + CGFloat(i) * 2.2, 19.9, 3.4 + CGFloat(i) * 2.2, 19.9, 0xB6BCC7, width: 0.5); c.vLine(3.2 + CGFloat(i) * 2.2, 21, 4 + CGFloat(i) * 2.2, 21, 0xB6BCC7, width: 0.5) }
        c.vRR(12.8, 18.6, 1.9, 3.4, 0.95, fill: 0xF6F7FA, stroke: 0xA7ADB8, line: 0.3)
    }

    /// MacBook: açık dizüstü, uzay grisi/gümüş, ekran + klavye şeridi. 16x32.
    static func drawMacBook(_ c: CGContext, _ color: OfficeComputer.Color, _ frame: Int?) {
        let b = macbookBodies[color] ?? macbookBodies[.silver]!
        c.vShadow(8, 18.4, 7.6, 1.5, 0.2)
        // ekran kapağı
        c.vRR(2.2, 3.6, 11.6, 8.8, 1, fill: 0x14171C, stroke: b.key, line: 0.35)
        screenContent(c, x: 3.1, y: 4.5, w: 9.8, h: 6.6, frame: frame)
        // taban (ince yamuk)
        c.vPoly([CGPoint(x: 1.2, y: 17.2), CGPoint(x: 2.6, y: 12.6), CGPoint(x: 13.4, y: 12.6), CGPoint(x: 14.8, y: 17.2)], fill: b.body, stroke: b.key, line: 0.35)
        c.vRR(1.0, 16.8, 14, 1.2, 0.6, fill: b.key)
        for r in 0..<2 { for i in 0..<6 {
            c.vRR(3.6 + CGFloat(i) * 1.5 - CGFloat(r) * 0.2, 13.4 + CGFloat(r) * 1.3, 1.1, 0.8, 0.25, fill: b.key, alpha: 0.85)
        } }
        c.vRR(6.4, 15.6, 3.2, 0.9, 0.3, fill: b.key, alpha: 0.7)
    }
}
