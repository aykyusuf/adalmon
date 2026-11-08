import CoreGraphics
import Foundation

// Vektör tema: oda başına TEK pişirilmiş arka plan (zemin + duvar + pencereler + gün ışığı + sabit mobilya) ve pencere dokusu.
// Koordinatlar düzen koordinatıdır (col*16, row*16; y aşağı); pişirme `bounds` başlangıcına öteler.

extension OfficeVectorArt {
    /// Pencere kutusu (çerçeve + denizlik), duvarın boş sütunlarında karo içinde ortalı.
    static let windowSize = CGSize(width: 14, height: 20)
    static let windowTop: CGFloat = 3.2

    struct BakedRoom {
        var image: CGImage
        /// Pencere kutuları (bounds başlangıcına göre mantıksal birim, y aşağı).
        var windows: [CGRect]
    }

    private static func isTemplateRoom(_ layout: OfficeLayout) -> Int? {
        guard layout.cols > 3, layout.rows > 3 else { return nil }
        for r in 0..<layout.rows where layout.kind(1, r) == .wall { return r }
        return nil
    }

    /// Duvarın boş (duvar mobilyası olmayan) sütunlarındaki pencere kutuları (düzen koordinatı).
    static func windowRects(layout: OfficeLayout, catalog: [String: OfficeAsset]) -> [CGRect] {
        guard isTemplateRoom(layout) != nil else { return [] }
        var occupied = Set<Int>()
        for f in layout.furniture {
            guard let a = catalog[f.assetID], a.onWall else { continue }
            for c in f.col..<(f.col + a.footprintW) { occupied.insert(c) }
        }
        return (1..<(layout.cols - 1)).filter { !occupied.contains($0) }.map {
            CGRect(x: CGFloat($0 * 16) + 1, y: windowTop, width: windowSize.width, height: windowSize.height)
        }
    }

    /// Pencere: beyaz çerçeve, gündüz gökyüzü degradesi + bulut ya da gece lacivert + yıldız/şehir ışıkları.
    static func drawWindow(_ c: CGContext, night: Bool) {
        let w = windowSize.width, glassH: CGFloat = 15.2
        c.vRR(0, 0, w, glassH + 2.4, 1.4, fill: 0xFBFAF6, stroke: 0xBDB5A4, line: 0.4)
        let gx: CGFloat = 1.2, gy: CGFloat = 1.2, gw = w - 2.4, gh = glassH - 0.0
        c.saveGState()
        c.addPath(CGPath(roundedRect: CGRect(x: gx, y: gy, width: gw, height: gh), cornerWidth: 0.7, cornerHeight: 0.7, transform: nil)); c.clip()
        let sky = night ? P.nightSky : P.sky
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c.vc(sky[0]), c.vc(sky[1])] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: gy), end: CGPoint(x: 0, y: gy + gh), options: [])
        if night {
            for (x, y, r) in [(2.4, 2.2, 0.35), (6.4, 3.4, 0.3), (10.2, 2.0, 0.4), (4.4, 6.0, 0.3), (9.0, 6.8, 0.3), (11.6, 5.0, 0.28)] as [(CGFloat, CGFloat, CGFloat)] {
                c.vOval(x - r, y - r, r * 2, r * 2, fill: 0xFFFFFF, alpha: 0.9)
            }
            c.vOval(8.6, 2.6, 2.6, 2.6, fill: 0xF3F0D8, alpha: 0.95)
            c.vOval(9.5, 2.3, 2.4, 2.4, fill: 0x16224A)
            for (i, x) in ([1.6, 3.2, 4.6, 6.4, 8.0, 9.8, 11.0] as [CGFloat]).enumerated() {
                let hh = CGFloat(1.6 + Double((i * 5) % 4) * 0.7)
                c.vRR(x, gy + gh - hh, 1.1, hh, 0.15, fill: 0x1A2756)
                if i % 2 == 0 { c.vRR(x + 0.3, gy + gh - hh + 0.4, 0.4, 0.4, 0.1, fill: 0xFFD27A) }
            }
        } else {
            c.vOval(1.6, 3.2, 5.6, 2.0, fill: 0xFFFFFF, alpha: 0.85); c.vOval(3.4, 2.4, 3.4, 2.0, fill: 0xFFFFFF, alpha: 0.85)
            c.vOval(7.6, 6.8, 5.0, 1.8, fill: 0xFFFFFF, alpha: 0.7)
            c.vPoly([CGPoint(x: gx, y: gy + gh), CGPoint(x: gx, y: gy + gh - 2.4), CGPoint(x: gx + 4, y: gy + gh - 3.4), CGPoint(x: gx + 8, y: gy + gh - 2), CGPoint(x: gx + gw, y: gy + gh - 3), CGPoint(x: gx + gw, y: gy + gh)], fill: 0xA8D5B5, alpha: 0.75)
        }
        c.restoreGState()
        c.vLine(w / 2, gy, w / 2, gy + gh, 0xFBFAF6, width: 0.7)
        c.vLine(gx, gy + gh * 0.5, gx + gw, gy + gh * 0.5, 0xFBFAF6, width: 0.7)
        c.vRR(-0.2, glassH + 1.2, w + 0.4, 1.8, 0.7, fill: 0xEDE6D8, stroke: 0xBDB5A4, line: 0.3)
    }

    static func windowImage(night: Bool) -> CGImage? { render(Int(windowSize.width), Int(windowSize.height)) { drawWindow($0, night: night) } }

    /// Zemin tahtaları: geniş açık meşe, hafif ton farkı, ince derz çizgileri (sürekli desen).
    private static func drawFloor(_ c: CGContext, _ r: CGRect) {
        c.saveGState()
        c.clip(to: r)
        c.setFillColor(c.vc(P.floorBase)); c.fill(r)
        let plankH: CGFloat = 8, plankLen: CGFloat = 40
        let rowsN = Int((r.height / plankH).rounded(.up))
        for k in 0..<rowsN {
            let y = r.minY + CGFloat(k) * plankH
            let shift = CGFloat((k * 13) % 40) - plankLen
            var n = 0
            var x = r.minX + shift
            while x < r.maxX {
                let tone = P.floorTones[(k * 3 + n * 5 + (k / 2)) % P.floorTones.count]
                let seg = CGRect(x: x, y: y, width: plankLen, height: plankH)
                c.setFillColor(c.vc(tone)); c.fill(seg.intersection(r))
                c.setFillColor(c.vc(P.plankLine, 0.32)); c.fill(CGRect(x: x, y: y, width: 0.3, height: plankH))
                x += plankLen; n += 1
            }
            c.setFillColor(c.vc(P.plankLine, 0.32)); c.fill(CGRect(x: r.minX, y: y + plankH - 0.3, width: r.width, height: 0.3))
            c.setFillColor(c.vc(0xFFFFFF, 0.10)); c.fill(CGRect(x: r.minX, y: y, width: r.width, height: 0.5))
        }
        c.restoreGState()
    }

    private static func drawCarpet(_ c: CGContext, _ z: CGRect) {
        let r = z.insetBy(dx: 3, dy: 3)
        c.vRR(r.minX + 0.5, r.minY + 1.2, r.width, r.height, 3.6, fill: 0x2A2118, alpha: 0.12)
        c.vRR(r.minX, r.minY, r.width, r.height, 3.6, fill: P.carpet, stroke: 0x7490B2, line: 0.4)
        c.vRR(r.minX + 2.2, r.minY + 2.2, r.width - 4.4, r.height - 4.4, 2.2, stroke: P.carpetBorder, line: 0.7)
        c.saveGState()
        c.addPath(CGPath(roundedRect: r.insetBy(dx: 3.4, dy: 3.4), cornerWidth: 1.4, cornerHeight: 1.4, transform: nil)); c.clip()
        var y = r.minY + 4.4
        while y < r.maxY - 3 {
            var x = r.minX + 5 + (Int(y / 6) % 2 == 0 ? 0 : 3)
            while x < r.maxX - 4 { c.vOval(x - 0.4, y - 0.4, 0.8, 0.8, fill: P.carpetDot, alpha: 0.6); x += 6 }
            y += 6
        }
        c.restoreGState()
    }

    /// Odanın pişirilmiş arka planı (gündüz): şablon odası değilse nil (çağıran piksel pişirmeye döner).
    @MainActor
    static func bakeRoom(layout: OfficeLayout, catalog: [String: OfficeAsset],
                         bounds b: (minCol: Int, minRow: Int, maxCol: Int, maxRow: Int)) -> BakedRoom? {
        guard let wallRow = isTemplateRoom(layout) else { return nil }
        let W = (b.maxCol - b.minCol + 1) * 16, H = (b.maxRow - b.minRow + 1) * 16
        var minC = Int.max, maxC = Int.min, minR = Int.max, maxR = Int.min
        for r in 0..<layout.rows { for col in 0..<layout.cols { if case .floor = layout.kind(col, r) {
            minC = min(minC, col); maxC = max(maxC, col); minR = min(minR, r); maxR = max(maxR, r)
        } } }
        guard minC != Int.max else { return nil }
        let floorRect = CGRect(x: minC * 16, y: minR * 16, width: (maxC - minC + 1) * 16, height: (maxR - minR + 1) * 16)
        let wallTop = CGFloat(max(0, wallRow - 1) * 16), wallH: CGFloat = 32
        let totalW = CGFloat(layout.cols * 16)
        let windows = windowRects(layout: layout, catalog: catalog)
        let baked = layout.furniture.compactMap { f -> (OfficeFurniturePlacement, OfficeAsset)? in
            guard let a = catalog[f.assetID], OfficeAssets.isBaked(a) else { return nil }
            return (f, a)
        }.sorted {
            func z(_ x: (OfficeFurniturePlacement, OfficeAsset)) -> Int { (x.1.onWall ? -1000 : 0) + (x.0.row + x.1.footprintH) * 16 + (x.1.onSurface ? 10_000 : 0) }
            return z($0) < z($1)
        }
        let image = render(W, H) { c in
            c.translateBy(x: -CGFloat(b.minCol * 16), y: -CGFloat(b.minRow * 16))
            drawFloor(c, floorRect)
            if let z = layout.executiveZone { drawCarpet(c, CGRect(x: z.minCol * 16, y: z.minRow * 16, width: (z.maxCol - z.minCol + 1) * 16, height: (z.maxRow - z.minRow + 1) * 16)) }
            // duvar gölgeleri (zemine): arka duvarın altı, yan duvarların içi
            let sh1 = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c.vc(0x2A2118, 0.20), c.vc(0x2A2118, 0)] as CFArray, locations: [0, 1])!
            c.saveGState(); c.clip(to: floorRect)
            c.drawLinearGradient(sh1, start: CGPoint(x: 0, y: wallTop + wallH), end: CGPoint(x: 0, y: wallTop + wallH + 7), options: [])
            c.drawLinearGradient(sh1, start: CGPoint(x: floorRect.minX, y: 0), end: CGPoint(x: floorRect.minX + 6, y: 0), options: [])
            c.drawLinearGradient(sh1, start: CGPoint(x: floorRect.maxX, y: 0), end: CGPoint(x: floorRect.maxX - 6, y: 0), options: [])
            c.restoreGState()
            // gün ışığı hüzmeleri (yumuşak çapraz paralelkenar, düşük alfa, statik)
            c.saveGState(); c.clip(to: floorRect)
            for win in windows {
                let x = win.minX + 1
                let p = CGMutablePath()
                p.addLines(between: [CGPoint(x: x, y: wallTop + wallH), CGPoint(x: x + 11, y: wallTop + wallH), CGPoint(x: x + 29, y: wallTop + wallH + 38), CGPoint(x: x + 18, y: wallTop + wallH + 38)])
                p.closeSubpath()
                c.saveGState(); c.addPath(p); c.clip()
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c.vc(0xFFF6DA, 0.34), c.vc(0xFFF6DA, 0)] as CFArray, locations: [0, 1])!
                c.drawLinearGradient(g, start: CGPoint(x: x, y: wallTop + wallH), end: CGPoint(x: x + 20, y: wallTop + wallH + 38), options: [])
                c.restoreGState()
            }
            c.restoreGState()
            // arka duvar
            c.vGradRR(0, wallTop, totalW, wallH, 0, top: 0xF8F4EC, bottom: P.wall)
            c.setFillColor(c.vc(P.wallEdge)); c.fill(CGRect(x: 0, y: wallTop, width: totalW, height: 2))
            c.setFillColor(c.vc(0xFFFFFF, 0.6)); c.fill(CGRect(x: 0, y: wallTop + 2, width: totalW, height: 0.4))
            c.setFillColor(c.vc(P.accent)); c.fill(CGRect(x: 0, y: wallTop + 21.2, width: totalW, height: 2.2))
            c.setFillColor(c.vc(P.accentDark, 0.8)); c.fill(CGRect(x: 0, y: wallTop + 23.2, width: totalW, height: 0.4))
            c.setFillColor(c.vc(P.skirting)); c.fill(CGRect(x: 0, y: wallTop + wallH - 3, width: totalW, height: 3))
            c.setFillColor(c.vc(0xFFFFFF, 0.5)); c.fill(CGRect(x: 0, y: wallTop + wallH - 3, width: totalW, height: 0.4))
            // yan duvarlar (karo genişliğinde; iç kenarda açık şerit)
            for (x0, inner) in [(0.0, 14.4), (totalW - 16, 0.0)] as [(CGFloat, CGFloat)] {
                let rect = CGRect(x: x0, y: wallTop, width: 16, height: CGFloat(H) + CGFloat(b.minRow * 16) - wallTop)
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c.vc(0xEFE9DC), c.vc(P.sideWall)] as CFArray, locations: [0, 1])!
                c.saveGState(); c.clip(to: rect)
                c.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
                c.restoreGState()
                c.setFillColor(c.vc(P.wallEdge)); c.fill(CGRect(x: x0 + inner, y: wallTop, width: 1.6, height: rect.height))
                c.setFillColor(c.vc(0xFFFFFF, 0.5)); c.fill(CGRect(x: x0 + (inner == 0 ? 1.6 : inner - 0.4), y: wallTop + 2, width: 0.4, height: rect.height - 2))
            }
            // pencereler
            for win in windows {
                c.saveGState(); c.translateBy(x: win.minX, y: win.minY); drawWindow(c, night: false); c.restoreGState()
            }
            // sabit mobilya
            for (f, a) in baked {
                c.saveGState()
                if f.mirrored { c.translateBy(x: CGFloat(f.col * 16 + a.width), y: CGFloat(f.row * 16)); c.scaleBy(x: -1, y: 1) }
                else { c.translateBy(x: CGFloat(f.col * 16), y: CGFloat(f.row * 16)) }
                drawFurniture(c, a.id, CGFloat(a.width), CGFloat(a.height))
                c.restoreGState()
            }
        }
        guard let image else { return nil }
        let off = CGPoint(x: CGFloat(b.minCol * 16), y: CGFloat(b.minRow * 16))
        return BakedRoom(image: image, windows: windows.map { $0.offsetBy(dx: -off.x, dy: -off.y) })
    }
}
