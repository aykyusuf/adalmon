import AppKit

struct BatteryGlyphOptions: Codable, Equatable, Sendable {
    enum Size: String, Codable, CaseIterable, Identifiable, Sendable {
        case small, medium, large
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .small: "Küçük"
            case .medium: "Orta"
            case .large: "Büyük"
            }
        }
    }

    /// Menü çubuğundaki sıvı dolgunun hareketi (yalnızca Mac pili).
    enum Animation: String, Codable, CaseIterable, Identifiable, Sendable {
        case off, light, live
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .off: "Kapalı"
            case .light: "Hafif"
            case .live: "Canlı"
            }
        }
    }

    var showTime = false
    var statusColors = true
    var size: Size = .medium
    /// (`animation` adı SwiftUI `Binding.animation(_:)` ile çakışır; JSON anahtarı yine "animation".)
    var motion: Animation = .live

    init(showTime: Bool = false, statusColors: Bool = true, size: Size = .medium, motion: Animation = .live) {
        self.showTime = showTime
        self.statusColors = statusColors
        self.size = size
        self.motion = motion
    }

    private enum CodingKeys: String, CodingKey { case showTime, statusColors, size
        case motion = "animation"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showTime = try c.decodeIfPresent(Bool.self, forKey: .showTime) ?? false
        statusColors = try c.decodeIfPresent(Bool.self, forKey: .statusColors) ?? true
        size = (try? c.decodeIfPresent(Size.self, forKey: .size)) ?? .medium
        motion = (try? c.decodeIfPresent(Animation.self, forKey: .motion)) ?? .live
    }
}

/// Menü çubuğu pil çizimi için gereken en küçük durum (zaman damgası yok; render anahtarı bununla karşılaştırır).
struct BatteryGlyphState: Equatable, Hashable, Sendable {
    var level: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var isFull: Bool
    var timeText: String?
    var lowPowerMode: Bool
    /// Cihaz pili ise cihaz simgesi (SF Symbol) ve "~" (yaklaşık) bilgisi.
    var deviceSymbol: String?
    var isApproximate = false

    init(device d: DeviceBattery) {
        level = d.summaryLevel ?? 0
        isCharging = d.isCharging
        isPluggedIn = false
        isFull = false
        timeText = nil
        lowPowerMode = false
        deviceSymbol = d.kind.symbol
        isApproximate = d.isApproximate
    }

    init(_ r: BatteryReading) {
        level = r.level
        isCharging = r.isCharging
        isPluggedIn = r.isPluggedIn
        isFull = r.state == .full
        timeText = BatteryFormat.menuBarTime(r)
        lowPowerMode = r.lowPowerMode
    }
}

/// Pil gövdesinin bu çizimde nasıl çizileceği: düz (statik), canlı dalganın belirli bir fazında ya da hiç (animasyonda
/// gövde ayrı, önceden hazırlanmış karelerden üstüne bindirilir).
enum BatteryCapsuleRender: Equatable, Sendable {
    case flat
    case wave(phase: Double, amplitude: CGFloat)
    case hidden
}

/// "Dolgulu sıvı pil": yuvarlak köşeli gövde + sağda uç, içi seviye kadar renkli sıvı, üstünde kalın yüzde; şarjda
/// şimşek gövdenin içinde, yazının solunda. Yazı ve şimşek sıvının üstünde kalan kısımda zıt renkle kırpılır.
enum BatteryGlyph {
    struct Metrics: Equatable {
        var body: CGSize
        var radius: CGFloat
        var nub: CGSize
        var font: CGFloat
        var timeFont: CGFloat
        var stroke: CGFloat
        var inset: CGFloat
    }

    static func metrics(_ size: BatteryGlyphOptions.Size) -> Metrics {
        switch size {
        // Orta = Juicy'nin gerçek pili (ekran görüntüsüyle ölçüldü): ~29x14 pt gövde + uç ≈ 32 pt, kalın ~10 pt rakam.
        case .small: Metrics(body: CGSize(width: 26, height: 12.5), radius: 4, nub: CGSize(width: 2, height: 5),
                             font: 7.5, timeFont: 10, stroke: 1.1, inset: 1.5)
        case .medium: Metrics(body: CGSize(width: 29, height: 14), radius: 4.5, nub: CGSize(width: 2.2, height: 5.5),
                              font: 9, timeFont: 11, stroke: 1.2, inset: 1.6)
        case .large: Metrics(body: CGSize(width: 33, height: 16), radius: 5, nub: CGSize(width: 2.5, height: 6.5),
                             font: 10.5, timeFont: 12, stroke: 1.3, inset: 1.8)
        }
    }

    /// Bir dalga döngüsündeki kare sayısı (nabız ve parıltı da bu döngüde tam tur atar → kare önbelleği N kare).
    static let frameCount = 24
    private static let gap: CGFloat = 3
    private static let nubGap: CGFloat = 1

    /// Animasyon modunun dalga genliği (pt).
    static func amplitude(_ animation: BatteryGlyphOptions.Animation) -> CGFloat {
        switch animation {
        case .off: 0
        case .light: 0.6
        case .live: 1.0
        }
    }

    /// "~" öneki gövdenin biraz genişlemesini ister.
    static func bodyWidth(_ m: Metrics, _ state: BatteryGlyphState?) -> CGFloat { m.body.width + (state?.isApproximate == true ? 5 : 0) }
    /// Gövde + uç (önbellekteki kare görüntüsünün boyutu).
    static func capsuleSize(_ m: Metrics, _ state: BatteryGlyphState?) -> CGSize {
        CGSize(width: bodyWidth(m, state) + nubGap + m.nub.width, height: m.body.height)
    }

    private static func timeFont(_ m: Metrics) -> NSFont { .monospacedDigitSystemFont(ofSize: m.timeFont, weight: .semibold) }
    static func levelFont(_ m: Metrics, size: CGFloat? = nil) -> NSFont {
        // Orantılı rakamlar: gövde genişliği sabit, "100" ve şimşek rahat sığar.
        let points = size ?? m.font
        let base = NSFont.systemFont(ofSize: points, weight: .bold)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: points) ?? base
    }

    static func boltSize(innerHeight: CGFloat) -> CGSize {
        CGSize(width: round(innerHeight * 0.55 * 2) / 2, height: innerHeight * 0.86)
    }
    static let boltSpacing: CGFloat = 1.5

    /// Yazı + (varsa) şimşek gövde içine en az 1 pt payla sığana dek küçülen yazı tipi (yalnızca "⚡100" gibi uç durumlar).
    static func contentFont(_ m: Metrics, text: String, bolt: Bool, innerWidth: CGFloat, innerHeight: CGFloat) -> NSFont {
        let extra = bolt ? boltSize(innerHeight: innerHeight).width + boltSpacing : 0
        var points = m.font
        var font = levelFont(m, size: points)
        while (text as NSString).size(withAttributes: [.font: font]).width + extra > innerWidth - 2, points > m.font * 0.7 {
            points -= 0.5
            font = levelFont(m, size: points)
        }
        return font
    }

    private static func textWidth(_ s: String, _ font: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    static func showsBolt(_ state: BatteryGlyphState) -> Bool { state.isCharging || (state.isPluggedIn && !state.isFull) }

    private static let deviceIconWidth: CGFloat = 14

    /// Mac ya da sabitlenmiş cihaz durumu.
    static func state(_ c: MenuBarComponent, _ values: WidgetValues) -> BatteryGlyphState? {
        guard let id = c.deviceID else { return values.battery }
        return values.devices[id]
    }

    /// Bu bileşen sürekli canlı sıvıyla çizilebilir mi (yalnızca Mac pili; cihaz pilleri statik).
    static func isAnimatable(_ c: MenuBarComponent) -> Bool {
        c.visual == .batteryCapsule && c.deviceID == nil && c.battery.motion != .off
    }

    // MARK: Cihaz öğesi ("📱 32%")

    private static var deviceFont: NSFont { .monospacedDigitSystemFont(ofSize: 13, weight: .semibold) }

    static func deviceText(_ state: BatteryGlyphState?) -> String {
        guard let state else { return "–%" }
        return (state.isApproximate ? "~" : "") + "\(state.level)%"
    }

    /// Metin rengi: düşük seviyede turuncu / kırmızı (durum renkleri açıksa), aksi halde sistem etiket rengi.
    static func deviceTint(_ c: MenuBarComponent, _ state: BatteryGlyphState?) -> NSColor? {
        guard c.battery.statusColors, let state, !state.isCharging else { return nil }
        if state.level <= 10 { return .systemRed }
        if state.level < 20 { return .systemOrange }
        return nil
    }

    private static func deviceWidth(_ c: MenuBarComponent, _ state: BatteryGlyphState?) -> CGFloat {
        var w = deviceIconWidth + gap + textWidth(deviceText(state), deviceFont)
        if state?.isCharging == true { w += 9 - 3 }
        return ceil(w)
    }

    private static func drawDevice(_ c: MenuBarComponent, _ state: BatteryGlyphState?, in rect: CGRect) {
        var x = rect.minX
        let midY = rect.midY
        WidgetGraphics.symbol(state?.deviceSymbol ?? "dot.radiowaves.left.and.right",
                              in: CGRect(x: x, y: midY - 7, width: deviceIconWidth, height: 14), color: .labelColor)
        x += deviceIconWidth + gap
        if state?.isCharging == true {
            WidgetGraphics.symbol("bolt.fill", in: CGRect(x: x - 2, y: midY - 5.5, width: 9, height: 11), color: .systemGreen)
            x += 9 - 3
        }
        let color = deviceTint(c, state) ?? NSColor.labelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: deviceFont, .foregroundColor: color]
        let text = deviceText(state) as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: x, y: midY - size.height / 2 + 0.3), withAttributes: attrs)
    }

    // MARK: Ölçü

    static func width(_ c: MenuBarComponent, values: WidgetValues) -> CGFloat {
        if c.deviceID != nil { return deviceWidth(c, state(c, values)) }
        let m = metrics(c.battery.size)
        let state = state(c, values)
        var w = capsuleSize(m, state).width
        if state?.deviceSymbol != nil { w += deviceIconWidth + gap }
        if c.battery.showTime, let t = state?.timeText { w += gap + textWidth(t, timeFont(m)) }
        return ceil(w)
    }

    /// Gövde+uç dikdörtgeni (bileşen yuvası içinde, yarım noktaya hizalı). Animasyon kareleri buraya bindirilir.
    static func capsuleRect(_ c: MenuBarComponent, values: WidgetValues, in rect: CGRect) -> CGRect {
        let m = metrics(c.battery.size)
        let state = state(c, values)
        var x = rect.minX
        if state?.deviceSymbol != nil { x += deviceIconWidth + gap }
        let size = capsuleSize(m, state)
        let y = rect.midY - size.height / 2
        // Yarım noktaya hizala (2x ekranda tam piksel).
        return CGRect(x: (x * 2).rounded() / 2, y: (y * 2).rounded() / 2, width: size.width, height: size.height)
    }

    static func tint(_ c: MenuBarComponent, _ state: BatteryGlyphState) -> NSColor? {
        tint(statusColors: c.battery.statusColors, state)
    }

    static func tint(statusColors: Bool, _ state: BatteryGlyphState) -> NSColor? {
        guard statusColors else { return nil }
        if state.isCharging { return .systemGreen }
        if state.lowPowerMode && !state.isPluggedIn { return .systemYellow }
        if state.isPluggedIn { return nil }
        if state.level <= 10 { return .systemRed }
        if state.level <= 20 { return .systemOrange }
        return nil
    }

    /// Pilde ve %20'nin altında: kırmızı nabız.
    static func pulses(_ state: BatteryGlyphState) -> Bool { !state.isCharging && !state.isPluggedIn && state.level < 20 }

    // MARK: Çizim

    static func draw(_ c: MenuBarComponent, values: WidgetValues, in rect: CGRect, capsule render: BatteryCapsuleRender = .flat) {
        if c.deviceID != nil { drawDevice(c, state(c, values), in: rect); return }
        let m = metrics(c.battery.size)
        let capsule = capsuleRect(c, values: values, in: rect)
        guard let state = state(c, values) else {
            drawPlaceholder(m, in: capsule)
            return
        }
        if let symbol = state.deviceSymbol {
            WidgetGraphics.symbol(symbol, in: CGRect(x: rect.minX, y: rect.midY - 7, width: deviceIconWidth, height: 14), color: .labelColor)
        }
        switch render {
        case .hidden: break
        // Cihaz pilleri her zaman sakin (düz) çizilir.
        case .flat: drawCapsule(state, options: c.battery, level: Double(state.level), in: capsule, wave: nil)
        case .wave(let phase, let amplitude):
            let wave = state.deviceSymbol == nil ? (phase, amplitude) : nil
            drawCapsule(state, options: c.battery, level: Double(state.level), in: capsule, wave: wave)
        }
        if c.battery.showTime, let t = state.timeText {
            let tf = timeFont(m)
            let a: [NSAttributedString.Key: Any] = [.font: tf, .foregroundColor: NSColor.labelColor]
            let s = (t as NSString).size(withAttributes: a)
            (t as NSString).draw(at: NSPoint(x: capsule.maxX + gap, y: rect.midY - s.height / 2 + 0.3), withAttributes: a)
        }
    }

    /// Sıvı yüzeyinin dolgu yüksekliği (pt): seviye 0 → 0; seviye > 0 ise en az ince bir çizgi görünür.
    static func fillHeight(level: Double, innerHeight: CGFloat) -> CGFloat {
        let l = max(0, min(100, level))
        guard l > 0 else { return 0 }
        return max(1.2, innerHeight * CGFloat(l) / 100)
    }

    /// Dalga genliği yalnızca boş uçta (<= %3) söner; tam dolu pilde de yüzey dalgalanır (sürekli canlı görünüm).
    static func taperedAmplitude(_ amplitude: CGFloat, level: Double) -> CGFloat {
        let l = CGFloat(max(0, min(100, level)))
        return amplitude * min(1, l / 3)
    }

    /// Dalga açıkken %88'in üstünde sıvı üst kenardan en çok 1.5 pt aşağı iner → %100'de de görünür bir yüzey kalır.
    static func fullLevelDrop(level: Double) -> CGFloat {
        let t = CGFloat(max(0, min(1, (level - 88) / 12)))
        return 1.5 * t * t * (3 - 2 * t)
    }

    /// Yüzey yüksekliği: iki sinüs, farklı dalga boyu ve faz; ikincisi iki kat hızlı ters yönde (döngü N karede kapanır).
    static func surfaceOffset(x: CGFloat, width: CGFloat, phase: Double) -> CGFloat {
        let u = Double(x / max(width, 1))
        let a = sin(2 * .pi * (u / 0.85 + phase))
        let b = sin(2 * .pi * (u / 0.47 - 2 * phase) + 1.7)
        return CGFloat(0.65 * a + 0.35 * b)
    }

    /// Nabız: 0…1 (faz 0'da en parlak), döngüde bir tur.
    static func pulse(phase: Double) -> CGFloat { CGFloat(0.5 + 0.5 * cos(2 * .pi * phase)) }

    private static func liquidPath(inner: CGRect, level: Double, wave: (phase: Double, amplitude: CGFloat)?) -> NSBezierPath? {
        let h = fillHeight(level: level, innerHeight: inner.height)
        guard h > 0 else { return nil }
        let amp = wave.map { taperedAmplitude($0.amplitude, level: level) } ?? 0
        let top = inner.minY + h - (amp > 0 ? fullLevelDrop(level: level) : 0)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: inner.minX - 1, y: inner.minY - 1))
        if amp > 0, let wave {
            var x = inner.minX - 1
            while x <= inner.maxX + 1 {
                path.line(to: CGPoint(x: x, y: top + amp * surfaceOffset(x: x - inner.minX, width: inner.width, phase: wave.phase)))
                x += 0.5
            }
        } else {
            path.line(to: CGPoint(x: inner.minX - 1, y: top))
            path.line(to: CGPoint(x: inner.maxX + 1, y: top))
        }
        path.line(to: CGPoint(x: inner.maxX + 1, y: inner.minY - 1))
        path.close()
        return path
    }

    /// Sıvının üstündeki yazı rengi: dolgu açık renkse koyu, koyuysa beyaz (mevcut görünümde çözülmüş renkle).
    static func contrastingText(on fill: NSColor) -> NSColor {
        guard let c = fill.usingColorSpace(.sRGB) else { return .white }
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let lum = 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
        // Yarı saydam dolgu menü çubuğuyla karışır; alfa düşükse etiket rengi daha güvenli.
        if c.alphaComponent < 0.5 { return .labelColor }
        return lum > 0.36 ? NSColor(white: 0.08, alpha: 1) : .white
    }

    static func boltPath(in r: CGRect) -> NSBezierPath {
        let p = NSBezierPath()
        let pts: [(CGFloat, CGFloat)] = [(0.62, 1.0), (0.0, 0.42), (0.43, 0.42), (0.33, 0.0), (1.0, 0.6), (0.57, 0.6)]
        for (i, pt) in pts.enumerated() {
            let point = CGPoint(x: r.minX + pt.0 * r.width, y: r.minY + pt.1 * r.height)
            if i == 0 { p.move(to: point) } else { p.line(to: point) }
        }
        p.close()
        p.lineJoinStyle = .round
        return p
    }

    /// Gövde + uç + sıvı + yazı/şimşek. `capsule` = `capsuleSize` büyüklüğünde dikdörtgen. `level` kesirli olabilir
    /// (seviye geçişi); yazı her zaman gerçek seviyeyi gösterir.
    static func drawCapsule(_ state: BatteryGlyphState, options: BatteryGlyphOptions, level: Double, in capsule: CGRect,
                            wave: (phase: Double, amplitude: CGFloat)?) {
        let m = metrics(options.size)
        let body = CGRect(x: capsule.minX, y: capsule.minY, width: bodyWidth(m, state), height: m.body.height)
        let tint = tint(statusColors: options.statusColors, state)
        let pulsing = pulses(state) && wave != nil
        let pulse = wave.map { pulse(phase: $0.phase) } ?? 1

        // Uç.
        let nub = CGRect(x: body.maxX + nubGap, y: body.midY - m.nub.height / 2, width: m.nub.width, height: m.nub.height)
        let nubPath = NSBezierPath(roundedRect: nub, xRadius: m.nub.width * 0.7, yRadius: m.nub.width * 0.7)
        let neutralStroke = NSColor.labelColor.withAlphaComponent(0.6)
        (tint?.withAlphaComponent(0.85) ?? neutralStroke).setFill()
        nubPath.fill()

        // Gövde çerçevesi ve boş kısmın hafif zemini.
        let outline = NSBezierPath(roundedRect: body.insetBy(dx: m.stroke / 2, dy: m.stroke / 2), xRadius: m.radius, yRadius: m.radius)
        outline.lineWidth = m.stroke
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        outline.fill()
        var strokeColor = tint?.withAlphaComponent(0.95) ?? neutralStroke
        if pulsing && options.statusColors {
            strokeColor = NSColor.systemRed.withAlphaComponent(0.55 + 0.45 * pulse)
        }
        strokeColor.setStroke()
        outline.stroke()

        // Sıvı.
        let inner = body.insetBy(dx: m.inset, dy: m.inset)
        let innerRadius = max(1.5, m.radius - m.inset + 0.4)
        let innerClip = NSBezierPath(roundedRect: inner, xRadius: innerRadius, yRadius: innerRadius)
        let baseFill = tint ?? NSColor.labelColor.withAlphaComponent(0.9)
        let liquid = liquidPath(inner: inner, level: level, wave: wave)
        if let liquid {
            NSGraphicsContext.saveGraphicsState()
            innerClip.addClip()
            var fill = baseFill
            if pulsing { fill = fill.withAlphaComponent(fill.alphaComponent * (0.62 + 0.38 * pulse)) }
            fill.setFill()
            liquid.fill()
            // Şarjda belirgin, doluyken / prizdeyken daha hafif, soldan sağa kayan parıltı.
            if state.isCharging || state.isFull || state.isPluggedIn, let wave {
                liquid.addClip()
                let band = inner.width * 0.4
                let t = wave.phase - floor(wave.phase)
                let cx = inner.minX - band / 2 + (inner.width + band) * CGFloat(t)
                let gradient = NSGradient(colors: [.white.withAlphaComponent(0), .white.withAlphaComponent(state.isCharging ? 0.38 : 0.24), .white.withAlphaComponent(0)])
                gradient?.draw(in: CGRect(x: cx - band / 2, y: inner.minY, width: band, height: inner.height), angle: 0)
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        // Yazı (+ şimşek): boş kısımda etiket rengi, sıvı üstünde zıt renk.
        let text = (state.isApproximate ? "~" : "") + "\(state.level)"
        let bolt = showsBolt(state)
        let font = contentFont(m, text: text, bolt: bolt, innerWidth: inner.width, innerHeight: inner.height)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let boltSize = boltSize(innerHeight: inner.height)
        let spacing: CGFloat = bolt ? boltSpacing : 0
        let contentWidth = textSize.width + (bolt ? boltSize.width + spacing : 0)
        var x = inner.midX - contentWidth / 2
        let boltRect = CGRect(x: x, y: inner.midY - boltSize.height / 2, width: boltSize.width, height: boltSize.height)
        if bolt { x += boltSize.width + spacing }
        // Rakamların görsel merkezi: cap height'a göre dikeyde ortala.
        let baselineY = inner.midY - font.capHeight / 2
        let textOrigin = CGPoint(x: x, y: baselineY + font.descender)

        func drawContent(_ color: NSColor) {
            if bolt {
                color.setFill()
                boltPath(in: boltRect).fill()
            }
            (text as NSString).draw(at: textOrigin, withAttributes: [.font: font, .foregroundColor: color])
        }

        let onFill = contrastingText(on: baseFill)
        NSGraphicsContext.saveGraphicsState()
        if let liquid {
            // Sıvının dışında kalan bölge.
            let outside = NSBezierPath(rect: body.insetBy(dx: -2, dy: -2))
            outside.append(liquid)
            outside.windingRule = .evenOdd
            outside.addClip()
        }
        drawContent(.labelColor)
        NSGraphicsContext.restoreGraphicsState()
        if let liquid {
            NSGraphicsContext.saveGraphicsState()
            innerClip.addClip()
            liquid.addClip()
            drawContent(onFill)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func drawPlaceholder(_ m: Metrics, in capsule: CGRect) {
        let body = CGRect(x: capsule.minX, y: capsule.minY, width: m.body.width, height: m.body.height)
        let path = NSBezierPath(roundedRect: body.insetBy(dx: m.stroke / 2, dy: m.stroke / 2), xRadius: m.radius, yRadius: m.radius)
        path.lineWidth = m.stroke
        NSColor.labelColor.withAlphaComponent(0.35).setStroke()
        path.stroke()
        let nub = CGRect(x: body.maxX + nubGap, y: body.midY - m.nub.height / 2, width: m.nub.width, height: m.nub.height)
        NSColor.labelColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: nub, xRadius: m.nub.width * 0.7, yRadius: m.nub.width * 0.7).fill()
    }
}
