import AppKit

/// Çubuk, halka, çizgi grafik ve ağ grafiği gibi şekil çizimleri.
enum WidgetGraphics {
    static let verticalBarSize = CGSize(width: 5, height: 14)
    static let horizontalBarHeight: CGFloat = 5
    static let horizontalBarMinWidth: CGFloat = 40
    static let ringDiameter: CGFloat = 18
    static let ringThickness: CGFloat = 2.5
    static let sparklineSize = CGSize(width: 36, height: 16)
    static let networkChartSize = CGSize(width: 34, height: 18)
    static let dotDiameter: CGFloat = 8

    static func verticalBar(in r: CGRect, fraction: Double, color: NSColor) {
        let radius = min(2, r.width / 2)
        WidgetPalette.track.setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        let h = r.height * max(0.06, min(1, fraction))
        color.setFill()
        NSBezierPath(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: h), xRadius: radius, yRadius: radius).fill()
    }

    static func horizontalBar(in r: CGRect, fraction: Double, color: NSColor) {
        let radius = r.height / 2
        WidgetPalette.track.setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        let w = max(r.height, r.width * max(0, min(1, fraction)))
        color.setFill()
        NSBezierPath(roundedRect: CGRect(x: r.minX, y: r.minY, width: w, height: r.height), xRadius: radius, yRadius: radius).fill()
    }

    /// Saat 12'den saat yönünde dolan halka.
    static func ring(in r: CGRect, fraction: Double, color: NSColor) {
        let inset = ringThickness / 2
        let circle = r.insetBy(dx: inset, dy: inset)
        let center = CGPoint(x: circle.midX, y: circle.midY)
        let radius = circle.width / 2

        let track = NSBezierPath(ovalIn: circle)
        track.lineWidth = ringThickness
        WidgetPalette.track.setStroke()
        track.stroke()

        let f = max(0, min(1, fraction))
        guard f > 0.005 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
        arc.lineWidth = ringThickness
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    /// Alan dolgulu çizgi grafik. `scale` nil ise en büyük değere göre ölçeklenir.
    static func sparkline(in r: CGRect, values: [Double], scale: Double?, color: NSColor) {
        WidgetPalette.track.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
        guard values.count > 1 else { return }
        let top = max(scale ?? (values.max() ?? 1), 0.000_001)
        let step = r.width / CGFloat(values.count - 1)
        let inner = r.insetBy(dx: 0, dy: 1)
        let points = values.enumerated().map { i, v in
            CGPoint(x: r.minX + CGFloat(i) * step, y: inner.minY + inner.height * CGFloat(max(0, min(1, v / top))))
        }

        let area = NSBezierPath()
        area.move(to: CGPoint(x: points[0].x, y: r.minY))
        points.forEach { area.line(to: $0) }
        area.line(to: CGPoint(x: points[points.count - 1].x, y: r.minY))
        area.close()
        color.withAlphaComponent(0.3).setFill()
        area.fill()

        let line = NSBezierPath()
        line.move(to: points[0])
        points.dropFirst().forEach { line.line(to: $0) }
        line.lineWidth = 1.5
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        color.setStroke()
        line.stroke()
    }

    /// Ayna ağ grafiği: üst yarı yükleme, alt yarı indirme; her seri kendi en büyüğüne göre ölçeklenir.
    static func networkChart(in r: CGRect, up: [Double], down: [Double], upColor: NSColor, downColor: NSColor) {
        let mid = r.midY
        half(in: CGRect(x: r.minX, y: mid, width: r.width, height: r.height / 2), values: up, upward: true, color: upColor)
        half(in: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height / 2), values: down, upward: false, color: downColor)
        WidgetPalette.track.setFill()
        CGRect(x: r.minX, y: mid - 0.25, width: r.width, height: 0.5).fill()
    }

    private static func half(in r: CGRect, values: [Double], upward: Bool, color: NSColor) {
        guard values.count > 1 else { return }
        let top = max(values.max() ?? 0, 1_000)
        let step = r.width / CGFloat(values.count - 1)
        let base = upward ? r.minY : r.maxY
        let points = values.enumerated().map { i, v in
            let h = r.height * CGFloat(max(0, min(1, v / top)))
            return CGPoint(x: r.minX + CGFloat(i) * step, y: upward ? base + h : base - h)
        }
        let area = NSBezierPath()
        area.move(to: CGPoint(x: points[0].x, y: base))
        points.forEach { area.line(to: $0) }
        area.line(to: CGPoint(x: points[points.count - 1].x, y: base))
        area.close()
        color.withAlphaComponent(0.35).setFill()
        area.fill()
        let line = NSBezierPath()
        line.move(to: points[0])
        points.dropFirst().forEach { line.line(to: $0) }
        line.lineWidth = 1
        color.setStroke()
        line.stroke()
    }

    static func dot(in r: CGRect, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: r).fill()
    }

    /// SF Symbol'ü verilen renge boyayarak çizer.
    static func symbol(_ name: String, in r: CGRect, color: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config),
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = image.size
        let scale = min(1, r.width / size.width, r.height / size.height)
        let w = size.width * scale, h = size.height * scale
        let target = CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        image.draw(in: target)
        color.setFill()
        target.fill(using: .sourceAtop)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
