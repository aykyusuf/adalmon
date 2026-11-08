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

    /// Dolgunun içindeki hareketin biçimi (her biri seviye kadar dolu bölgede çizilir; döngü `frameCount` karede kapanır).
    enum Style: String, Codable, CaseIterable, Identifiable, Sendable {
        case liquid, beam, bubbles, stripes, breathe, aurora, ocean, segments, sparkle, ecg
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .liquid: "Sıvı"
            case .beam: "Huzme"
            case .bubbles: "Kabarcıklar"
            case .stripes: "Şeritler"
            case .breathe: "Nefes"
            case .aurora: "Aurora"
            case .ocean: "Okyanus"
            case .segments: "Segmentler"
            case .sparkle: "Kıvılcım"
            case .ecg: "Nabız"
            }
        }
        /// İkinci rengi kullanan stiller (gradyan / ikinci katman / şerit rengi).
        var usesSecondColor: Bool {
            switch self {
            case .aurora, .ocean, .stripes: true
            default: false
            }
        }
        /// Statik önizlemede stilin en iyi göründüğü faz (Huzme fazı 0'da kadraj dışında).
        var previewPhase: Double {
            switch self {
            case .beam: 0.4
            case .breathe: 0.5
            case .sparkle: 0.15
            default: 0.3
            }
        }
    }

    /// Hazır dolgu renkleri.
    enum Swatch: String, CaseIterable, Identifiable, Sendable {
        case green, blue, purple, pink, orange, teal, yellow, white
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .green: "Yeşil"
            case .blue: "Mavi"
            case .purple: "Mor"
            case .pink: "Pembe"
            case .orange: "Turuncu"
            case .teal: "Turkuaz"
            case .yellow: "Sarı"
            case .white: "Beyaz"
            }
        }
        var color: RGBAColor {
            switch self {
            case .green: RGBAColor(red: 0.20, green: 0.80, blue: 0.36)
            case .blue: RGBAColor(red: 0.04, green: 0.52, blue: 1.0)
            case .purple: RGBAColor(red: 0.69, green: 0.36, blue: 0.95)
            case .pink: RGBAColor(red: 1.0, green: 0.27, blue: 0.58)
            case .orange: RGBAColor(red: 1.0, green: 0.58, blue: 0.0)
            case .teal: RGBAColor(red: 0.16, green: 0.80, blue: 0.82)
            case .yellow: RGBAColor(red: 1.0, green: 0.82, blue: 0.04)
            case .white: RGBAColor(red: 0.88, green: 0.88, blue: 0.90)
            }
        }
    }

    var showTime = false
    var statusColors = true
    var size: Size = .medium
    /// (`animation` adı SwiftUI `Binding.animation(_:)` ile çakışır; JSON anahtarı yine "animation".)
    var motion: Animation = .live
    var style: Style = .liquid
    /// `nil` = otomatik (durum renkleri paleti); aksi halde hazır ya da özel dolgu rengi.
    var fillColor: RGBAColor?
    /// Gradyan / ikinci katman rengi; `nil` = birinci renkten türetilir.
    var secondColor: RGBAColor?

    init(showTime: Bool = false, statusColors: Bool = true, size: Size = .medium, motion: Animation = .live,
         style: Style = .liquid, fillColor: RGBAColor? = nil, secondColor: RGBAColor? = nil) {
        self.showTime = showTime
        self.statusColors = statusColors
        self.size = size
        self.motion = motion
        self.style = style
        self.fillColor = fillColor
        self.secondColor = secondColor
    }

    private enum CodingKeys: String, CodingKey { case showTime, statusColors, size, style, fillColor, secondColor
        case motion = "animation"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showTime = try c.decodeIfPresent(Bool.self, forKey: .showTime) ?? false
        statusColors = try c.decodeIfPresent(Bool.self, forKey: .statusColors) ?? true
        size = (try? c.decodeIfPresent(Size.self, forKey: .size)) ?? .medium
        motion = (try? c.decodeIfPresent(Animation.self, forKey: .motion)) ?? .live
        style = (try? c.decodeIfPresent(Style.self, forKey: .style)) ?? .liquid
        fillColor = (try? c.decodeIfPresent(RGBAColor.self, forKey: .fillColor)) ?? nil
        secondColor = (try? c.decodeIfPresent(RGBAColor.self, forKey: .secondColor)) ?? nil
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
    static let frameCount = 30
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

static func customAlert(_ state: BatteryGlyphState) -> Bool {
        !state.isCharging && !state.isPluggedIn && state.level <= 10
    }

    static func baseFill(_ options: BatteryGlyphOptions, _ state: BatteryGlyphState) -> NSColor {
        if let fill = options.fillColor { return fill.nsColor }
        return tint(statusColors: options.statusColors, state) ?? NSColor.labelColor.withAlphaComponent(0.9)
    }

    static func secondFill(_ options: BatteryGlyphOptions, base: NSColor) -> NSColor {
        if let second = options.secondColor { return second.nsColor }
        guard let c = base.usingColorSpace(.sRGB) else { return base }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.15 { return NSColor(white: b > 0.5 ? 0.55 : 0.85, alpha: a) }
        let shifted = (h + 0.13).truncatingRemainder(dividingBy: 1)
        return NSColor(hue: shifted, saturation: min(1, s * 1.05), brightness: min(1, b * 1.02 + 0.04), alpha: a)
    }

    static func luminance(_ color: NSColor) -> CGFloat {
        guard let c = color.usingColorSpace(.sRGB) else { return 0.5 }
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    private static func sheen(on fill: NSColor) -> (color: NSColor, scale: CGFloat) {
        luminance(fill) > 0.55 ? (.black, 0.65) : (.white, 1)
    }

    private struct StyleContext {
        var inner: CGRect
        var top: CGFloat
        var phase: Double
        var intensity: CGFloat
        var fill: NSColor
        var second: NSColor
        var hasCustomSecond: Bool
        var charging: Bool
        var fillHeight: CGFloat { max(0, top - inner.minY) }
    }

    private static func frac(_ v: Double) -> Double { v - floor(v) }
    private static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private static func surfacePath(inner: CGRect, top: CGFloat, amplitude: CGFloat,
                                    offset: ((CGFloat) -> CGFloat)?) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: inner.minX - 1, y: inner.minY - 1))
        if amplitude > 0, let offset {
            var x = inner.minX - 1
            while x <= inner.maxX + 1 {
                path.line(to: CGPoint(x: x, y: top + amplitude * offset(x - inner.minX)))
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

    static func backSurfaceOffset(x: CGFloat, width: CGFloat, phase: Double) -> CGFloat {
        let u = Double(x / max(width, 1))
        return CGFloat(0.7 * sin(2 * .pi * (u / 0.62 - phase) + 0.9) + 0.3 * sin(2 * .pi * (u / 0.31 + phase) + 2.2))
    }

    static func frontSurfaceOffset(x: CGFloat, width: CGFloat, phase: Double) -> CGFloat {
        let u = Double(x / max(width, 1))
        return CGFloat(0.75 * sin(2 * .pi * (u / 0.9 + 2 * phase)) + 0.25 * sin(2 * .pi * (u / 0.38 + phase) + 1.1))
    }

    static func ecgValue(_ u: Double) -> Double {
        switch u {
        case 0.10..<0.20: return 0.14 * sin(.pi * (u - 0.10) / 0.10)
        case 0.27..<0.30: return -0.18 * (u - 0.27) / 0.03
        case 0.30..<0.335: return -0.18 + 1.18 * (u - 0.30) / 0.035
        case 0.335..<0.375: return 1 - 1.4 * (u - 0.335) / 0.04
        case 0.375..<0.41: return -0.4 + 0.4 * (u - 0.375) / 0.035
        case 0.52..<0.68: return 0.26 * sin(.pi * (u - 0.52) / 0.16)
        default: return 0
        }
    }

    private static func fillGradient(_ colors: [NSColor], in rect: CGRect, angle: CGFloat = 0) {
        NSGradient(colors: colors)?.draw(in: rect, angle: angle)
    }

    private static func drawBeam(_ c: StyleContext) {
        let t = c.phase / 0.75
        guard t < 1, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let (color, scale) = sheen(on: c.fill)
        let band = max(8, c.inner.width * 0.45)
        // Eğim payı (±yükseklik/2 * 0.55) + yarım bant: başta tamamen sağda, sonda tamamen solda (dikişsiz).
        let margin = band / 2 + c.inner.height * 0.3
        let span = c.inner.width + 2 * margin
        // Hafif yavaşlayan sabit hızlı süpürme.
        let eased = CGFloat(t * (1.15 - 0.15 * t))
        let cx = c.inner.maxX + margin - span * eased
        ctx.saveGState()
        ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0.55, d: 1, tx: cx - 0.55 * c.inner.midY, ty: 0))
        let peak = 0.5 * c.intensity * scale
        fillGradient([color.withAlphaComponent(0), color.withAlphaComponent(peak), color.withAlphaComponent(0)],
                     in: CGRect(x: -band / 2, y: c.inner.minY - 2, width: band, height: c.inner.height + 4))
        let core = band * 0.28
        fillGradient([color.withAlphaComponent(0), color.withAlphaComponent(peak * 0.9), color.withAlphaComponent(0)],
                     in: CGRect(x: -core / 2 + band * 0.08, y: c.inner.minY - 2, width: core, height: c.inner.height + 4))
        ctx.restoreGState()
    }

    private static let bubbles: [(x: CGFloat, r: CGFloat, speed: Double, offset: Double, wobble: CGFloat)] = [
        (0.08, 0.85, 1, 0.00, 0.4), (0.21, 0.65, 2, 0.35, 0.3), (0.34, 1.05, 1, 0.62, 0.5),
        (0.50, 0.70, 2, 0.12, 0.3), (0.63, 0.95, 1, 0.84, 0.45), (0.77, 0.6, 2, 0.58, 0.3),
        (0.90, 0.9, 1, 0.30, 0.4),
    ]

    private static func drawBubbles(_ c: StyleContext) {
        let (color, scale) = sheen(on: c.fill)
        let h = c.fillHeight
        guard h > 1.5 else { return }
        for b in bubbles {
            let r = min(b.r, h * 0.3)
            let travel = h + 2 * r
            let f = frac(c.phase * b.speed + b.offset)
            let y = c.inner.minY - r + travel * CGFloat(f)
            let x = c.inner.minX + b.x * c.inner.width + b.wobble * CGFloat(sin(2 * .pi * (c.phase * 2 + b.offset)))
            let fade = CGFloat(1 - smooth(0.78, 1, f)) * CGFloat(smooth(0, 0.12, f))
            guard fade > 0.01 else { continue }
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            let circle = NSBezierPath(ovalIn: rect)
            color.withAlphaComponent(0.20 * c.intensity * scale * fade).setFill()
            circle.fill()
            circle.lineWidth = 0.5
            color.withAlphaComponent(0.85 * c.intensity * scale * fade).setStroke()
            circle.stroke()
            color.withAlphaComponent(0.9 * c.intensity * scale * fade).setFill()
            NSBezierPath(ovalIn: CGRect(x: x - r * 0.45, y: y + r * 0.15, width: r * 0.42, height: r * 0.42)).fill()
        }
    }

    private static func drawStripes(_ c: StyleContext) {
        let period: CGFloat = 5
        let width: CGFloat = 2.2
        let (sheenColor, scale) = sheen(on: c.fill)
        let color = c.hasCustomSecond ? c.second.withAlphaComponent(0.75 * c.intensity + 0.15)
                                      : sheenColor.withAlphaComponent(0.24 * c.intensity * scale)
        color.setFill()
        let h = c.inner.height + 2
        let offset = period * CGFloat(c.phase)
        var x = c.inner.minX - h - period + offset
        let path = NSBezierPath()
        while x < c.inner.maxX + period {
            path.move(to: CGPoint(x: x, y: c.inner.minY - 1))
            path.line(to: CGPoint(x: x + width, y: c.inner.minY - 1))
            path.line(to: CGPoint(x: x + width + h, y: c.inner.minY - 1 + h))
            path.line(to: CGPoint(x: x + h, y: c.inner.minY - 1 + h))
            path.close()
            x += period
        }
        path.fill()
    }

    private static func drawBreathe(_ c: StyleContext, liquid: NSBezierPath) {
        let b = CGFloat(0.5 - 0.5 * cos(2 * .pi * c.phase))
        let (color, scale) = sheen(on: c.fill)
        NSColor.black.withAlphaComponent(0.16 * c.intensity * (1 - b)).setFill()
        liquid.fill()
        color.withAlphaComponent(0.26 * c.intensity * b * scale).setFill()
        liquid.fill()
        let glowH = max(2, c.fillHeight * 0.55)
        fillGradient([color.withAlphaComponent(0), color.withAlphaComponent(0.22 * c.intensity * b * scale)],
                     in: CGRect(x: c.inner.minX, y: c.top - glowH, width: c.inner.width, height: glowH), angle: 90)
    }

    private static func drawAurora(_ c: StyleContext) {
        let w = c.inner.width + 2
        let x0 = c.inner.minX - 1 - w * CGFloat(c.phase)
        let colors = [c.fill, c.second, c.fill]
        for i in 0..<2 {
            fillGradient(colors, in: CGRect(x: x0 + CGFloat(i) * w, y: c.inner.minY - 1, width: w, height: c.inner.height + 2))
        }
        let (color, scale) = sheen(on: c.fill)
        let shimmer = CGFloat(0.5 + 0.5 * sin(2 * .pi * c.phase))
        fillGradient([color.withAlphaComponent(0), color.withAlphaComponent((0.10 + 0.08 * shimmer) * c.intensity * scale)],
                     in: CGRect(x: c.inner.minX, y: c.inner.minY, width: c.inner.width, height: c.fillHeight), angle: 90)
    }

    private static func drawSegments(_ c: StyleContext) {
        let n = max(6, Int((c.inner.width / 2.75).rounded()))
        let cell = c.inner.width / CGFloat(n)
        let gap: CGFloat = 0.6
        let (color, scale) = sheen(on: c.fill)
        for i in 0..<n {
            let u = (Double(i) + 0.5) / Double(n)
            let b = pow(max(0, cos(2 * .pi * (u - c.phase))), 3)
            guard b > 0.01 else { continue }
            color.withAlphaComponent(0.46 * c.intensity * scale * CGFloat(b)).setFill()
            CGRect(x: c.inner.minX + CGFloat(i) * cell, y: c.inner.minY - 1, width: cell, height: c.inner.height + 2).fill()
        }
        NSColor.black.withAlphaComponent(0.28).setFill()
        for i in 1..<n {
            CGRect(x: c.inner.minX + CGFloat(i) * cell - gap / 2, y: c.inner.minY - 1, width: gap, height: c.inner.height + 2).fill()
        }
    }

    private static let sparks: [(x: CGFloat, y: CGFloat, size: CGFloat, freq: Double, offset: Double)] = [
        (0.10, -1, 1.9, 1, 0.00), (0.30, -1, 1.5, 2, 0.40), (0.52, -1, 2.1, 1, 0.55), (0.74, -1, 1.6, 2, 0.15),
        (0.92, -1, 1.9, 1, 0.78), (0.18, 0.35, 1.3, 2, 0.70), (0.44, 0.22, 1.2, 1, 0.25), (0.66, 0.40, 1.4, 2, 0.90),
        (0.86, 0.25, 1.2, 1, 0.45), (0.97, 0.60, 1.5, 1, 0.12),
    ]

    private static func starPath(center p: CGPoint, radius r: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let k = r * 0.22
        let pts = [CGPoint(x: 0, y: r), CGPoint(x: k, y: k), CGPoint(x: r, y: 0), CGPoint(x: k, y: -k),
                   CGPoint(x: 0, y: -r), CGPoint(x: -k, y: -k), CGPoint(x: -r, y: 0), CGPoint(x: -k, y: k)]
        for (i, pt) in pts.enumerated() {
            let q = CGPoint(x: p.x + pt.x, y: p.y + pt.y)
            if i == 0 { path.move(to: q) } else { path.line(to: q) }
        }
        path.close()
        return path
    }

    private static func drawSparkle(_ c: StyleContext) {
        let h = c.fillHeight
        guard h > 0.8 else { return }
        let color = luminance(c.fill) > 0.55 ? c.fill.blended(withFraction: 0.65, of: .black) ?? .black : NSColor.white
        for s in sparks {
            let tw = pow(max(0, sin(2 * .pi * (c.phase * s.freq + s.offset))), 3)
            guard tw > 0.02 else { continue }
            let x = c.inner.minX + s.x * c.inner.width
            let y = s.y < 0 ? c.top - min(1.6, h * 0.5) : c.inner.minY + s.y * h
            let r = s.size * CGFloat(0.55 + 0.45 * tw) * (0.8 + 0.2 * c.intensity)
            color.withAlphaComponent(CGFloat(tw) * (0.55 + 0.45 * c.intensity)).setFill()
            starPath(center: CGPoint(x: x, y: y), radius: r).fill()
            color.withAlphaComponent(CGFloat(tw) * 0.25 * c.intensity).setFill()
            NSBezierPath(ovalIn: CGRect(x: x - r * 0.55, y: y - r * 0.55, width: r * 1.1, height: r * 1.1)).fill()
        }
    }

    private static func drawECG(_ c: StyleContext) {
        let h = c.fillHeight
        guard h > 2 else { return }
        let (color, scale) = sheen(on: c.fill)
        let y0 = c.inner.minY + h * 0.42
        let amp = min(c.inner.height * 0.42, h * 0.5)
        let path = NSBezierPath()
        var x = c.inner.minX - 1
        while x <= c.inner.maxX + 1 {
            let u = frac(Double((x - c.inner.minX) / c.inner.width) + c.phase)
            let pt = CGPoint(x: x, y: y0 + amp * CGFloat(ecgValue(u)))
            if path.isEmpty { path.move(to: pt) } else { path.line(to: pt) }
            x += 0.25
        }
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.lineWidth = 2.2
        color.withAlphaComponent(0.16 * c.intensity * scale).setStroke()
        path.stroke()
        path.lineWidth = 0.85
        color.withAlphaComponent((0.55 + 0.35 * c.intensity) * scale).setStroke()
        path.stroke()
    }

    private static func drawOceanBack(_ c: StyleContext, amplitude: CGFloat) {
        let back = surfacePath(inner: c.inner, top: c.top + 0.8, amplitude: amplitude * 1.35) {
            backSurfaceOffset(x: $0, width: c.inner.width, phase: c.phase)
        }
        c.second.withAlphaComponent(c.second.alphaComponent * 0.62).setFill()
        back.fill()
    }

    static func drawCapsule(_ state: BatteryGlyphState, options: BatteryGlyphOptions, level: Double, in capsule: CGRect,
                            wave: (phase: Double, amplitude: CGFloat)?) {
        let m = metrics(options.size)
        let body = CGRect(x: capsule.minX, y: capsule.minY, width: bodyWidth(m, state), height: m.body.height)
        let custom = options.fillColor != nil
        let alert = custom && customAlert(state)
        let tint: NSColor? = custom ? (alert ? .systemRed : nil) : tint(statusColors: options.statusColors, state)
        let pulsing = (custom ? alert : pulses(state)) && wave != nil
        let pulse = wave.map { pulse(phase: $0.phase) } ?? 1
        let style = options.style

        let nub = CGRect(x: body.maxX + nubGap, y: body.midY - m.nub.height / 2, width: m.nub.width, height: m.nub.height)
        let nubPath = NSBezierPath(roundedRect: nub, xRadius: m.nub.width * 0.7, yRadius: m.nub.width * 0.7)
        let neutralStroke = NSColor.labelColor.withAlphaComponent(0.6)
        (tint?.withAlphaComponent(0.85) ?? neutralStroke).setFill()
        nubPath.fill()

        let outline = NSBezierPath(roundedRect: body.insetBy(dx: m.stroke / 2, dy: m.stroke / 2), xRadius: m.radius, yRadius: m.radius)
        outline.lineWidth = m.stroke
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        outline.fill()
        var strokeColor = tint?.withAlphaComponent(0.95) ?? neutralStroke
        if pulsing && (options.statusColors || custom) {
            strokeColor = NSColor.systemRed.withAlphaComponent(0.55 + 0.45 * pulse)
        }
        strokeColor.setStroke()
        outline.stroke()

        let inner = body.insetBy(dx: m.inset, dy: m.inset)
        let innerRadius = max(1.5, m.radius - m.inset + 0.4)
        let innerClip = NSBezierPath(roundedRect: inner, xRadius: innerRadius, yRadius: innerRadius)
        var baseFill = baseFill(options, state)
        if alert { baseFill = baseFill.blended(withFraction: 0.5, of: .systemRed) ?? .systemRed }
        let second = secondFill(options, base: baseFill)

        let h = fillHeight(level: level, innerHeight: inner.height)
        let waved = wave != nil && (style == .liquid || style == .ocean)
        let amp = waved ? wave.map { taperedAmplitude($0.amplitude * (style == .ocean ? 0.8 : 1), level: level) } ?? 0 : 0
        let top = inner.minY + h - (amp > 0 ? fullLevelDrop(level: level) * (style == .ocean ? 1.3 : 1) : 0)
        let liquid: NSBezierPath? = h > 0 ? surfacePath(inner: inner, top: top, amplitude: amp) { x in
            style == .ocean ? frontSurfaceOffset(x: x, width: inner.width, phase: wave?.phase ?? 0)
                            : surfaceOffset(x: x, width: inner.width, phase: wave?.phase ?? 0)
        } : nil

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
        let baselineY = inner.midY - font.capHeight / 2
        let textOrigin = CGPoint(x: x, y: baselineY + font.descender)

        var fill = baseFill
        if let liquid {
            NSGraphicsContext.saveGraphicsState()
            innerClip.addClip()
            if pulsing {
                if custom {
                    fill = options.fillColor!.nsColor.blended(withFraction: 0.3 + 0.55 * pulse, of: .systemRed) ?? baseFill
                } else {
                    fill = fill.withAlphaComponent(fill.alphaComponent * (0.62 + 0.38 * pulse))
                }
            }
            if let wave, style == .ocean {
                drawOceanBack(StyleContext(inner: inner, top: top, phase: wave.phase, intensity: wave.amplitude, fill: fill,
                                           second: second, hasCustomSecond: options.secondColor != nil, charging: state.isCharging),
                              amplitude: taperedAmplitude(wave.amplitude, level: level))
            }
            fill.setFill()
            liquid.fill()
            liquid.addClip()
            if let wave {
                let ctx = StyleContext(inner: inner, top: top, phase: wave.phase, intensity: wave.amplitude, fill: fill,
                                       second: second, hasCustomSecond: options.secondColor != nil, charging: state.isCharging)
                switch style {
                case .liquid, .ocean:
                    if style == .ocean, amp > 0 {
                        let foam = surfacePath(inner: inner, top: top - 0.35, amplitude: amp) {
                            frontSurfaceOffset(x: $0, width: inner.width, phase: wave.phase)
                        }
                        let (color, scale) = sheen(on: fill)
                        color.withAlphaComponent(0.22 * scale).setStroke()
                        foam.lineWidth = 0.7
                        foam.stroke()
                    }
                    if state.isCharging || state.isFull || state.isPluggedIn {
                        let band = inner.width * 0.4
                        let t = wave.phase - floor(wave.phase)
                        let cx = inner.minX - band / 2 + (inner.width + band) * CGFloat(t)
                        let (color, scale) = sheen(on: fill)
                        let a = (state.isCharging ? 0.38 : 0.24) * scale
                        fillGradient([color.withAlphaComponent(0), color.withAlphaComponent(a), color.withAlphaComponent(0)],
                                     in: CGRect(x: cx - band / 2, y: inner.minY, width: band, height: inner.height))
                    }
                case .beam: drawBeam(ctx)
                case .bubbles: drawBubbles(ctx)
                case .stripes: drawStripes(ctx)
                case .breathe: drawBreathe(ctx, liquid: liquid)
                case .aurora: drawAurora(ctx)
                case .segments: drawSegments(ctx)
                case .sparkle: drawSparkle(ctx)
                case .ecg: drawECG(ctx)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        func drawContent(_ color: NSColor) {
            if bolt {
                color.setFill()
                boltPath(in: boltRect).fill()
            }
            (text as NSString).draw(at: textOrigin, withAttributes: [.font: font, .foregroundColor: color])
        }

        let textBase: NSColor = style == .aurora && wave != nil ? (baseFill.blended(withFraction: 0.5, of: second) ?? baseFill) : baseFill
        let onFill = contrastingText(on: textBase)
        NSGraphicsContext.saveGraphicsState()
        if let liquid {
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
            if wave != nil, [.bubbles, .stripes, .segments, .sparkle, .ecg].contains(style) {
                let halo = fill.withAlphaComponent(min(1, fill.alphaComponent + 0.1))
                if bolt {
                    let p = boltPath(in: boltRect)
                    p.lineWidth = 1.8
                    halo.setStroke()
                    p.stroke()
                }
                (text as NSString).draw(at: textOrigin, withAttributes: [.font: font, .strokeColor: halo, .strokeWidth: 24])
            }
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
