import AppKit
import CoreGraphics
import Foundation

// Ofis vektör teması: etiket "hapı", konuşma balonu, oda başlık kartı ve küçük karakter yardımcı dokuları (zzz, paspas, fincan, koli,
// "!" ve "…" balonları). 9-dilim (centerRect) dokular: genişlik metne göre uzar, köşe/kuyruk/gölge sabit kalır. Boyutlar ekran
// noktasında (düğüm ölçeği 1/zoom): mantıksal birim = 1 pt, doku 4x.

enum OfficeVectorUI {
    /// 9-dilim yuvarlak panel dokusu: mantıksal `w`×`h`, `pad` gölge boşluğu, `r` köşe yarıçapı.
    struct Panel: Sendable {
        var w: Int, h: Int, pad: CGFloat, r: CGFloat
        var fill: UInt32, fillAlpha: CGFloat, border: UInt32, borderAlpha: CGFloat, shadow: CGFloat
    }

    static let pillHeight: CGFloat = 15
    /// Etiket hapı: gündüz açık yüzey, gece koyu cam.
    static func labelPanel(night: Bool) -> Panel {
        night ? Panel(w: 30, h: 21, pad: 3, r: 7.5, fill: 0x1B2132, fillAlpha: 0.9, border: 0xFFFFFF, borderAlpha: 0.2, shadow: 0.3)
              : Panel(w: 30, h: 21, pad: 3, r: 7.5, fill: 0xFFFFFF, fillAlpha: 0.92, border: 0x11141C, borderAlpha: 0.16, shadow: 0.22)
    }

    /// Oda başlık kartı (koyu zemin üstünde): açık kart gündüz, koyu slate gece.
    static func cardPanel(night: Bool) -> Panel {
        night ? Panel(w: 32, h: 27, pad: 3, r: 9, fill: 0x2A3144, fillAlpha: 0.96, border: 0xFFFFFF, borderAlpha: 0.22, shadow: 0.35)
              : Panel(w: 32, h: 27, pad: 3, r: 9, fill: 0xF7F8FA, fillAlpha: 0.97, border: 0x11141C, borderAlpha: 0.18, shadow: 0.3)
    }

    /// Gövde genişliği `bodyWidth` (mantıksal birim, tamsayı) için panel dokusu: genişliğe göre üretilip önbelleklenir (SpriteKit 9-dilim
    /// 4x dokuda köşeleri 4 kat büyüttüğü için kullanılmaz).
    static func panelImage(_ p: Panel, bodyWidth: Int) -> CGImage? {
        OfficeVectorArt.render(bodyWidth + Int(2 * p.pad), p.h) { c in
            let bw = CGFloat(bodyWidth), bh = CGFloat(p.h) - 2 * p.pad
            for (i, grow) in [CGFloat(1.6), 1.0, 0.4].enumerated() {
                c.vRR(p.pad - grow, p.pad - grow + 1.0, bw + 2 * grow, bh + 2 * grow, p.r + grow, fill: 0x0A0C14, alpha: p.shadow * [0.18, 0.28, 0.4][i])
            }
            c.vRR(p.pad, p.pad, bw, bh, p.r, fill: p.fill, alpha: p.fillAlpha)
            c.vRR(p.pad + 0.2, p.pad + 0.2, bw - 0.4, bh - 0.4, p.r - 0.2, stroke: p.border, line: 0.4)
            c.setAlpha(1)
        }
    }

    /// Düz beyaz hap (renk `color` + `colorBlendFactor` 1 ile verilir): rozet, nokta, şerit. `width`×`height` mantıksal birim.
    static func solidImage(width: Int, height: Int) -> CGImage? {
        OfficeVectorArt.render(width, height) { c in c.vRR(0, 0, CGFloat(width), CGFloat(height), CGFloat(min(width, height)) / 2, fill: 0xFFFFFF) }
    }

    // MARK: Konuşma balonu

    static let bubblePad: CGFloat = 2
    static let bubbleBodyHeight: CGFloat = 14
    static let bubbleTail: CGFloat = 4
    /// Kuyruk ucundan gövde üstüne: 4 + 14.
    static let bubbleHeight: CGFloat = 18
    /// Kuyruk ucunun gövdenin sol kenarına uzaklığı (ekran pt).
    static let bubbleTipX: CGFloat = 4
    static let bubbleTexH = 22
    static let bubbleMinBody: CGFloat = 26

    static func bubbleImage(bodyWidth: Int) -> CGImage? {
        OfficeVectorArt.render(bodyWidth + Int(2 * bubblePad), bubbleTexH) { c in
            let p = bubblePad, bw = CGFloat(bodyWidth), bh = bubbleBodyHeight
            let tail: [CGPoint] = [CGPoint(x: 4.2, y: p + bh - 1), CGPoint(x: 9.4, y: p + bh - 1), CGPoint(x: 6.0, y: p + bh + bubbleTail)]
            for (i, grow) in [CGFloat(1.4), 0.8, 0.3].enumerated() {
                c.vRR(p - grow, p - grow + 0.9, bw + 2 * grow, bh + 2 * grow, 7 + grow, fill: 0x0A0C14, alpha: [0.08, 0.12, 0.17][i])
            }
            c.vPoly(tail, fill: 0xFFFFFF)
            c.vRR(p, p, bw, bh, 7, fill: 0xFFFFFF, stroke: 0x1A1D26, line: 0.35)
            c.vPoly(tail, fill: 0xFFFFFF)
            c.vLine(4.6, p + bh, 5.8, p + bh + bubbleTail - 0.4, 0x1A1D26, width: 0.35, alpha: 0.5)
            c.vLine(9.0, p + bh, 6.2, p + bh + bubbleTail - 0.4, 0x1A1D26, width: 0.35, alpha: 0.5)
        }
    }

    // MARK: Yazı

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSFont { NSFont.systemFont(ofSize: size, weight: weight) }

    static func text(_ s: String, size: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font(size, weight), .foregroundColor: color])
    }

    // MARK: Karakter yardımcı dokuları

    static let overlayNames = ["zzz", "mop", "cup", "box", "bubble_alert", "bubble_think"]

    static func overlaySize(_ name: String) -> CGSize? {
        switch name {
        case "zzz": CGSize(width: 9, height: 8)
        case "mop": CGSize(width: 7, height: 16)
        case "cup": CGSize(width: 6, height: 5)
        case "box": CGSize(width: 10, height: 7)
        case "bubble_alert": CGSize(width: 11, height: 12)
        case "bubble_think": CGSize(width: 11, height: 10)
        default: nil
        }
    }

    static func overlay(_ name: String) -> CGImage? {
        guard let s = overlaySize(name) else { return nil }
        return OfficeVectorArt.render(Int(s.width), Int(s.height)) { c in
            switch name {
            case "zzz":
                func z(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
                    c.setStrokeColor(c.vc(0x4F6FD0)); c.setLineWidth(0.85); c.setLineCap(.round); c.setLineJoin(.round)
                    c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x + w, y: y)); c.addLine(to: CGPoint(x: x, y: y + w)); c.addLine(to: CGPoint(x: x + w, y: y + w)); c.strokePath()
                }
                z(0.8, 5.2, 2.0); z(3.2, 2.8, 2.6); z(6.0, 0.6, 2.2)
            case "mop":
                c.vShadow(3.5, 15.4, 3.4, 0.7, 0.25)
                c.vRR(3.0, 0.4, 1.0, 11.2, 0.5, fill: 0xA37C45, stroke: 0x6B4E26, line: 0.3)
                c.vRR(2.4, 10.8, 2.2, 1.0, 0.4, fill: 0x9AA3B0, stroke: 0x5E6573, line: 0.25)
                c.vPath(CGPath(roundedRect: CGRect(x: 0.6, y: 11.6, width: 5.8, height: 3.8), cornerWidth: 1.4, cornerHeight: 1.4, transform: nil), fill: 0xD9E4F4, stroke: 0x8DA2C4, line: 0.35)
                for i in 0..<4 { c.vLine(1.5 + CGFloat(i) * 1.3, 12.8, 1.5 + CGFloat(i) * 1.3, 15.0, 0xFFFFFF, width: 0.45) }
            case "cup":
                c.vShadow(2.6, 4.6, 2.6, 0.5, 0.2)
                c.vRR(0.6, 0.8, 3.6, 3.6, 1.0, fill: 0xFAFAFA, stroke: 0x9A9AA6, line: 0.3)
                c.vOval(0.9, 1.0, 3.0, 1.0, fill: 0x6B3E1E)
                c.setStrokeColor(c.vc(0x9A9AA6)); c.setLineWidth(0.4)
                c.addArc(center: CGPoint(x: 4.4, y: 2.6), radius: 0.9, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false); c.strokePath()
            case "box":
                c.vShadow(5, 6.6, 4.6, 0.5, 0.22)
                c.vRR(0.6, 0.6, 8.8, 5.6, 0.9, fill: 0xC8964B, stroke: 0x7A5426, line: 0.35)
                c.vRR(0.6, 2.6, 8.8, 0.9, 0.2, fill: 0xE6C98A)
            case "bubble_alert":
                c.vPoly([CGPoint(x: 4.2, y: 8.8), CGPoint(x: 6.8, y: 8.8), CGPoint(x: 5.5, y: 11.4)], fill: 0xFFFFFF)
                c.vRR(0.6, 0.6, 9.8, 9.0, 4.5, fill: 0xFFFFFF, stroke: 0x1A1D26, line: 0.35)
                c.vPoly([CGPoint(x: 4.2, y: 8.8), CGPoint(x: 6.8, y: 8.8), CGPoint(x: 5.5, y: 11.4)], fill: 0xFFFFFF)
                c.vRR(4.7, 2.2, 1.6, 3.6, 0.8, fill: 0xFF8A00)
                c.vOval(4.7, 6.6, 1.6, 1.6, fill: 0xFF8A00)
            case "bubble_think":
                c.vPoly([CGPoint(x: 4.2, y: 7.4), CGPoint(x: 6.8, y: 7.4), CGPoint(x: 5.5, y: 9.6)], fill: 0xFFFFFF)
                c.vRR(0.6, 0.6, 9.8, 7.6, 3.8, fill: 0xFFFFFF, stroke: 0x1A1D26, line: 0.35)
                c.vPoly([CGPoint(x: 4.2, y: 7.4), CGPoint(x: 6.8, y: 7.4), CGPoint(x: 5.5, y: 9.6)], fill: 0xFFFFFF)
                for i in 0..<3 { c.vOval(2.3 + CGFloat(i) * 2.5, 3.5, 1.4, 1.4, fill: 0x6B7280) }
            default: break
            }
        }
    }
}
