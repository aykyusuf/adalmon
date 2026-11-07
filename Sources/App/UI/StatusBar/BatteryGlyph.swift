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

    var showTime = false
    var statusColors = true
    var size: Size = .medium

    init(showTime: Bool = false, statusColors: Bool = true, size: Size = .medium) {
        self.showTime = showTime
        self.statusColors = statusColors
        self.size = size
    }

    private enum CodingKeys: String, CodingKey { case showTime, statusColors, size }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showTime = try c.decodeIfPresent(Bool.self, forKey: .showTime) ?? false
        statusColors = try c.decodeIfPresent(Bool.self, forKey: .statusColors) ?? true
        size = (try? c.decodeIfPresent(Size.self, forKey: .size)) ?? .medium
    }
}

/// Menü çubuğu pil çizimi için gereken en küçük durum (zaman damgası yok; render anahtarı bununla karşılaştırır).
struct BatteryGlyphState: Equatable, Sendable {
    var level: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var isFull: Bool
    var timeText: String?
    var lowPowerMode: Bool

    init(_ r: BatteryReading) {
        level = r.level
        isCharging = r.isCharging
        isPluggedIn = r.isPluggedIn
        isFull = r.state == .full
        timeText = BatteryFormat.menuBarTime(r)
        lowPowerMode = r.lowPowerMode
    }
}

/// Kapsül pil: içinde yüzde, solda şarj şimşeği, sağda isteğe bağlı süre.
enum BatteryGlyph {
    private struct Metrics {
        var capsule: CGSize
        var font: CGFloat
        var timeFont: CGFloat
    }

    private static func metrics(_ size: BatteryGlyphOptions.Size) -> Metrics {
        switch size {
        case .small: Metrics(capsule: CGSize(width: 28, height: 12), font: 8.5, timeFont: 10)
        case .medium: Metrics(capsule: CGSize(width: 34, height: 14), font: 9.5, timeFont: 11)
        case .large: Metrics(capsule: CGSize(width: 40, height: 16), font: 11, timeFont: 12)
        }
    }

    private static let boltWidth: CGFloat = 9
    private static let gap: CGFloat = 3

    private static func timeFont(_ m: Metrics) -> NSFont { .monospacedDigitSystemFont(ofSize: m.timeFont, weight: .medium) }
    private static func levelFont(_ m: Metrics) -> NSFont { .monospacedDigitSystemFont(ofSize: m.font, weight: .semibold) }

    private static func textWidth(_ s: String, _ font: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func showsBolt(_ state: BatteryGlyphState) -> Bool { state.isCharging || (state.isPluggedIn && !state.isFull) }

    static func width(_ c: MenuBarComponent, values: WidgetValues) -> CGFloat {
        let m = metrics(c.battery.size)
        guard let state = values.battery else { return m.capsule.width }
        var w = m.capsule.width
        if showsBolt(state) { w += boltWidth + gap - 2 }
        if c.battery.showTime, let t = state.timeText { w += gap + textWidth(t, timeFont(m)) }
        return ceil(w)
    }

    static func tint(_ c: MenuBarComponent, _ state: BatteryGlyphState) -> NSColor? {
        guard c.battery.statusColors else { return nil }
        if state.isCharging { return .systemGreen }
        if state.lowPowerMode && !state.isPluggedIn { return .systemYellow }
        if state.isPluggedIn { return nil }
        if state.level <= 10 { return .systemRed }
        if state.level <= 20 { return .systemOrange }
        return nil
    }

    static func draw(_ c: MenuBarComponent, values: WidgetValues, in rect: CGRect) {
        let m = metrics(c.battery.size)
        guard let state = values.battery else {
            drawPlaceholder(m, in: rect)
            return
        }
        let tint = tint(c, state)
        var x = rect.minX
        let midY = rect.midY

        if showsBolt(state) {
            let color = (state.isCharging ? tint ?? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.7))
            WidgetGraphics.symbol("bolt.fill", in: CGRect(x: x - 1, y: midY - 5.5, width: boltWidth, height: 11), color: color)
            x += boltWidth + gap - 2
        }

        let capsule = CGRect(x: x, y: midY - m.capsule.height / 2, width: m.capsule.width, height: m.capsule.height)
        let radius = capsule.height / 2
        let outline = NSBezierPath(roundedRect: capsule.insetBy(dx: 0.6, dy: 0.6), xRadius: radius, yRadius: radius)
        outline.lineWidth = 1.2
        (tint?.withAlphaComponent(0.9) ?? NSColor.labelColor.withAlphaComponent(0.55)).setStroke()
        outline.stroke()

        // İç dolgu (seviyeye orantılı).
        let inner = capsule.insetBy(dx: 2, dy: 2)
        let fraction = CGFloat(max(0, min(100, state.level))) / 100
        if fraction > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: inner, xRadius: inner.height / 2, yRadius: inner.height / 2).addClip()
            (tint ?? NSColor.labelColor).withAlphaComponent(tint == nil ? 0.30 : 0.42).setFill()
            let fill = CGRect(x: inner.minX, y: inner.minY, width: max(inner.height, inner.width * fraction), height: inner.height)
            NSBezierPath(roundedRect: fill, xRadius: inner.height / 2, yRadius: inner.height / 2).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        let text = "\(state.level)"
        let font = levelFont(m)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: capsule.midX - size.width / 2, y: capsule.midY - size.height / 2 + 0.3), withAttributes: attrs)
        x = capsule.maxX

        if c.battery.showTime, let t = state.timeText {
            let tf = timeFont(m)
            let a: [NSAttributedString.Key: Any] = [.font: tf, .foregroundColor: NSColor.labelColor]
            let s = (t as NSString).size(withAttributes: a)
            (t as NSString).draw(at: NSPoint(x: x + gap, y: midY - s.height / 2 + 0.3), withAttributes: a)
        }
    }

    private static func drawPlaceholder(_ m: Metrics, in rect: CGRect) {
        let capsule = CGRect(x: rect.minX, y: rect.midY - m.capsule.height / 2, width: m.capsule.width, height: m.capsule.height)
        let path = NSBezierPath(roundedRect: capsule.insetBy(dx: 0.6, dy: 0.6), xRadius: capsule.height / 2, yRadius: capsule.height / 2)
        path.lineWidth = 1.2
        NSColor.labelColor.withAlphaComponent(0.35).setStroke()
        path.stroke()
    }
}
