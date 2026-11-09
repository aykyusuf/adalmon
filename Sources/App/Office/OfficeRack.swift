import CoreGraphics
import Foundation

/// Oda sunucu rafı (arka plan işlemleri): statik LED'ler (yanıp sönme YOK; pil). N → LED eşlemesi saf ve testlidir.
enum OfficeRackLED: String, Equatable, Sendable { case off, green, orange }

struct OfficeRackState: Equatable, Sendable {
    static let ledCount = 4
    var leds: [OfficeRackLED]
    /// Oturumun pid'i biliniyor mu (hayır: raf var ama gri, ipucu "İşlem bilgisi yok").
    var known: Bool
    var count: Int

    /// N=0 ya da pid bilinmiyor: hepsi sönük. 1…4: N yeşil. N>4: dört LED yanar, sonuncusu turuncu.
    static func make(total: Int, known: Bool) -> OfficeRackState {
        let n = known ? max(0, total) : 0
        var leds = [OfficeRackLED](repeating: .off, count: ledCount)
        for i in 0..<min(n, ledCount) { leds[i] = .green }
        if n > ledCount { leds[ledCount - 1] = .orange }
        return OfficeRackState(leds: leds, known: known, count: n)
    }

    static let idle = OfficeRackState.make(total: 0, known: false)

    var tooltip: String { known ? "Arka plan işlemleri: \(count)" : "İşlem bilgisi yok (eski oturum)" }
    var litCount: Int { leds.filter { $0 != .off }.count }
}

extension OfficeRackLED {
    var hex: UInt32 {
        switch self {
        case .off: 0x6B7280
        case .green: 0x4ADE80
        case .orange: 0xFFA73B
        }
    }
}

extension OfficeVectorArt {
    /// Raf gövdesi (LED'ler sönük). Mantıksal 16×32; bay i: y = 5 + 6i.
    static func serverRack(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
        c.vShadow(w / 2, h - 1.2, w * 0.44, 1.5, 0.28)
        c.vGradRR(1.6, 1.6, w - 3.2, h - 3.6, 1.8, top: 0x4A5366, bottom: 0x262C39, stroke: 0x171B24, line: 0.35)
        c.vRR(2.6, 2.4, w - 5.2, 0.9, 0.4, fill: 0xFFFFFF, alpha: 0.14)
        for i in 0..<OfficeRackState.ledCount {
            let y = rackBayY(i)
            c.vRR(2.8, y, w - 5.6, 4.6, 0.9, fill: 0x151922, stroke: 0x0F1218, line: 0.25)
            c.vRR(4, y + 1.2, 4.4, 0.7, 0.3, fill: 0x59627A)
            c.vRR(4, y + 2.7, 4.4, 0.7, 0.3, fill: 0x424A5E)
            c.vRR(rackLEDX, y + 1.8, 2.6, 1.1, 0.55, fill: OfficeRackLED.off.hex, alpha: 0.55)
        }
    }

    static let rackLEDX: CGFloat = 9.6
    static func rackBayY(_ i: Int) -> CGFloat { 5 + 6 * CGFloat(i) }

    /// Yalnızca LED'ler (gövdenin üstüne bindirilir). Vektör: yumuşak şeritler + hafif hale; piksel: 2×1 keskin kareler.
    static func rackLEDs(_ state: OfficeRackState, pixel: Bool) -> CGImage? {
        if pixel {
            guard let ctx = CGContext(data: nil, width: 16, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setShouldAntialias(false)
            for (i, led) in state.leds.enumerated() {
                let hex = led.hex
                ctx.setFillColor(CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1))
                // CG y yukarı: üstten y → 32 - y - yükseklik.
                ctx.fill(CGRect(x: 10, y: 32 - (5 + 6 * i + 2) - 1, width: 2, height: 1))
            }
            return ctx.makeImage()
        }
        return render(16, 32) { c in
            for (i, led) in state.leds.enumerated() {
                let y = rackBayY(i) + 1.8
                if led != .off { c.vRR(rackLEDX - 1, y - 1, 4.6, 3.1, 1.5, fill: led.hex, alpha: 0.22) }
                c.vRR(rackLEDX, y, 2.6, 1.1, 0.55, fill: led.hex, alpha: led == .off ? 0.55 : 1)
            }
        }
    }

    /// Web istemcisi için tek LED (5×4 mantıksal): hale + şerit. Konum: (rack.x + dotX, rack.y + dotY + i·dotDy).
    static func rackLEDDot(_ led: OfficeRackLED) -> CGImage? {
        render(5, 4) { c in
            if led != .off { c.vRR(0, 0, 4.6, 3.1, 1.5, fill: led.hex, alpha: 0.22) }
            c.vRR(1, 1, 2.6, 1.1, 0.55, fill: led.hex, alpha: led == .off ? 0.55 : 1)
        }
    }

    /// `/v1/layout` rack sözleşmesi: LED dokuları (data URI) ve yerleşim sabitleri.
    static func rackWebJSON() -> [String: Any] {
        var dots: [String: String] = [:]
        for led in [OfficeRackLED.off, .green, .orange] {
            if let img = rackLEDDot(led), let png = OfficeArt.pngData(img) { dots[led.rawValue] = "data:image/png;base64," + png.base64EncodedString() }
        }
        return ["w": 16, "h": 32, "ledCount": OfficeRackState.ledCount, "dotX": rackLEDX - 1, "dotY": rackBayY(0) + 0.8, "dotDy": 6, "dotW": 5, "dotH": 4,
                "dots": dots, "states": ["off", "green", "orange"]]
    }
}
