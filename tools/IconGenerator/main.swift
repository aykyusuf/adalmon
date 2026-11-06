// Adalmon app icon generator (CoreGraphics + ImageIO only, no dependencies).
//
// Usage:
//   swiftc -O tools/IconGenerator/main.swift -o /tmp/icongen
//   /tmp/icongen preview <a|b|c> <out.png> [--style fullbleed|masked|classic]
//   /tmp/icongen appiconset <a|b|c> <AppIcon.appiconset dir> [docs/icon-1024.png] [--style ...]
//   /tmp/icongen iconlayers <a|b|c> <AppIcon.icon dir>   # Icon Composer package: opaque background + glyph layer
//
// Variants: a = pulse line, b = gauge + up/down arrows, c = gauge + pulse line.
//
// Styles (macOS 26 Tahoe masks app icons itself, so the app icon must be an unmasked square):
//   fullbleed (default) opaque gradient edge to edge, no squircle/rim/shadow, glyph inside the central safe area.
//   masked    fullbleed artwork clipped to a squircle with a soft shadow; only for README/preview images.
//   classic   the old pre-Tahoe icon with a baked-in squircle, rim, sheen and drop shadow.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a,
    ])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

/// Apple-style continuous-corner squircle (superellipse) inscribed in `rect`.
func squircle(_ rect: CGRect, exponent n: CGFloat = 4.4) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    let cx = rect.midX, cy = rect.midY, a = rect.width / 2, b = rect.height / 2
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

// MARK: - Glyphs (drawn in 1024 space, origin bottom-left)

func pulsePath(yMid: CGFloat, x0: CGFloat, x1: CGFloat, amp: CGFloat) -> CGPath {
    let w = x1 - x0
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x0, y: yMid))
    p.addLine(to: CGPoint(x: x0 + w * 0.26, y: yMid))
    p.addLine(to: CGPoint(x: x0 + w * 0.40, y: yMid + amp))
    p.addLine(to: CGPoint(x: x0 + w * 0.58, y: yMid - amp * 1.05))
    p.addLine(to: CGPoint(x: x0 + w * 0.70, y: yMid + amp * 0.35))
    p.addLine(to: CGPoint(x: x0 + w * 0.78, y: yMid))
    p.addLine(to: CGPoint(x: x1, y: yMid))
    return p
}

func arrowPath(x: CGFloat, yTail: CGFloat, yHead: CGFloat, head: CGFloat) -> CGPath {
    let dir: CGFloat = yHead > yTail ? 1 : -1
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x, y: yTail))
    p.addLine(to: CGPoint(x: x, y: yHead))
    p.move(to: CGPoint(x: x - head, y: yHead - dir * head))
    p.addLine(to: CGPoint(x: x, y: yHead))
    p.addLine(to: CGPoint(x: x + head, y: yHead - dir * head))
    return p
}

func arcPath(center: CGPoint, radius: CGFloat, from: CGFloat, to: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addArc(center: center, radius: radius, startAngle: from, endAngle: to, clockwise: true)
    return p
}

/// Fills a stroked path with a linear gradient (top -> bottom of `bounds`).
func strokeWithGradient(_ g: CGContext, path: CGPath, width: CGFloat, grad: CGGradient, from: CGPoint, to: CGPoint) {
    g.saveGState()
    g.addPath(path)
    g.setLineWidth(width); g.setLineCap(.round); g.setLineJoin(.round)
    g.replacePathWithStrokedPath()
    g.clip()
    g.drawLinearGradient(grad, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    g.restoreGState()
}

/// Glow pass (coloured shadow) followed by a crisp gradient pass.
func glowStroke(_ g: CGContext, path: CGPath, width: CGFloat, glow: CGColor, blur: CGFloat, grad: CGGradient, from: CGPoint, to: CGPoint) {
    g.saveGState()
    g.setShadow(offset: .zero, blur: blur, color: glow)
    g.addPath(path)
    g.setStrokeColor(rgb(0xFFFFFF)); g.setLineWidth(width); g.setLineCap(.round); g.setLineJoin(.round)
    g.strokePath()
    g.restoreGState()
    strokeWithGradient(g, path: path, width: width, grad: grad, from: from, to: to)
}

let glyphWhite = gradient([(0, rgb(0xFFFFFF)), (1, rgb(0xCFF6FF))])
var glowAlpha: CGFloat = 0.85
var cyanGlow: CGColor { rgb(0x22D3EE, glowAlpha) }

// Stroke geometry shared by drawing and bounds measurement (1024 space).
let gaugeCenter = CGPoint(x: 512, y: 520)
let gaugeStart = CGFloat.pi * 1.25 // 225deg, bottom-left
func gaugeTrackPath() -> CGPath { arcPath(center: gaugeCenter, radius: 285, from: gaugeStart, to: -CGFloat.pi * 0.25) }
func gaugeProgressPath(_ end: CGFloat) -> CGPath { arcPath(center: gaugeCenter, radius: 285, from: gaugeStart, to: end) }
func arrowPaths() -> [CGPath] { // down on the left, up on the right
    [arrowPath(x: 418, yTail: 650, yHead: 390, head: 72), arrowPath(x: 606, yTail: 390, yHead: 650, head: 72)]
}
func pulseAPath() -> CGPath { pulsePath(yMid: 500, x0: 200, x1: 824, amp: 235) }
func pulseCPath() -> CGPath { pulsePath(yMid: 530, x0: 292, x1: 732, amp: 150) }

func variantProgressEnd(_ variant: String) -> CGFloat { CGFloat.pi * (variant == "b" ? 0.12 : 0.22) }

/// Union of the stroked outlines of the glyph (no glow), used to centre and scale it.
func glyphBounds(_ variant: String) -> CGRect {
    let strokes: [(CGPath, CGFloat)]
    switch variant {
    case "a": strokes = [(pulseAPath(), 66)]
    case "b": strokes = [(gaugeProgressPath(variantProgressEnd(variant)), 64)] + arrowPaths().map { ($0, 54) }
    default: strokes = [(gaugeProgressPath(variantProgressEnd(variant)), 64), (pulseCPath(), 54)]
    }
    return strokes.map { $0.0.copy(strokingWithWidth: $0.1, lineCap: .round, lineJoin: .round, miterLimit: 10).boundingBoxOfPath }
        .reduce(CGRect.null) { $0.union($1) }
}

func drawPulse(_ g: CGContext) {
    let path = pulseAPath()
    // faint "trail" under the line
    strokeWithGradient(g, path: path, width: 92, grad: gradient([(0, rgb(0xFFFFFF, 0.10)), (1, rgb(0xFFFFFF, 0.10))]), from: .zero, to: CGPoint(x: 0, y: 1))
    glowStroke(g, path: path, width: 66, glow: cyanGlow, blur: 36, grad: glyphWhite, from: CGPoint(x: 0, y: 760), to: CGPoint(x: 0, y: 260))
}

func drawGauge(_ g: CGContext, progressEnd: CGFloat) {
    strokeWithGradient(g, path: gaugeTrackPath(), width: 64, grad: gradient([(0, rgb(0xFFFFFF, 0.16)), (1, rgb(0xFFFFFF, 0.16))]), from: .zero, to: CGPoint(x: 0, y: 1))
    glowStroke(g, path: gaugeProgressPath(progressEnd), width: 64, glow: cyanGlow, blur: 34,
               grad: gradient([(0, rgb(0xA5F3FC)), (0.5, rgb(0xFFFFFF)), (1, rgb(0xFFFFFF))]),
               from: CGPoint(x: 230, y: 300), to: CGPoint(x: 760, y: 800))
}

func drawArrows(_ g: CGContext) {
    for p in arrowPaths() {
        glowStroke(g, path: p, width: 54, glow: cyanGlow, blur: 26, grad: glyphWhite, from: CGPoint(x: 0, y: 650), to: CGPoint(x: 0, y: 390))
    }
}

func drawGaugePulse(_ g: CGContext) {
    glowStroke(g, path: pulseCPath(), width: 54, glow: cyanGlow, blur: 26, grad: glyphWhite, from: CGPoint(x: 0, y: 690), to: CGPoint(x: 0, y: 360))
}

// MARK: - Icon

enum Style: String { case fullbleed, masked, classic }

/// Fraction of the canvas width the glyph occupies in the full-bleed icon (Apple: keep primary content centred / inside the safe zone).
let glyphCanvasFraction: CGFloat = 0.62

func drawGlyph(_ g: CGContext, variant: String) {
    switch variant {
    case "a": drawPulse(g)
    case "b": drawGauge(g, progressEnd: variantProgressEnd(variant)); drawArrows(g)
    default: drawGauge(g, progressEnd: variantProgressEnd(variant)); drawGaugePulse(g)
    }
}

/// Glyph centred on the canvas and scaled so its widest side is `glyphCanvasFraction` of the canvas.
func drawCenteredGlyph(_ g: CGContext, variant: String) {
    let b = glyphBounds(variant)
    let s = canvas * glyphCanvasFraction / max(b.width, b.height)
    g.saveGState()
    g.translateBy(x: canvas / 2, y: canvas / 2)
    g.scaleBy(x: s, y: s)
    g.translateBy(x: -b.midX, y: -b.midY)
    drawGlyph(g, variant: variant)
    g.restoreGState()
}

/// Edge-to-edge opaque gradient (deep indigo -> violet -> cyan, diagonal) with soft blooms.
func drawBackground(_ g: CGContext, in rect: CGRect) {
    g.saveGState()
    g.clip(to: rect)
    g.drawLinearGradient(gradient([(0, rgb(0x120B52)), (0.42, rgb(0x4B2BC4)), (0.78, rgb(0x6D44F0)), (1, rgb(0x16C5E8))]),
                         start: CGPoint(x: rect.minX + 0.1456 * rect.width, y: rect.maxY), end: CGPoint(x: rect.minX + 0.874 * rect.width, y: rect.minY),
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Cyan bloom bottom-right, violet bloom top-left for depth
    let c1 = CGPoint(x: rect.minX + 0.85 * rect.width, y: rect.minY + 0.085 * rect.height)
    g.drawRadialGradient(gradient([(0, rgb(0x22D3EE, 0.75)), (1, rgb(0x22D3EE, 0))]),
                         startCenter: c1, startRadius: 0, endCenter: c1, endRadius: 0.63 * rect.width, options: [])
    let c2 = CGPoint(x: rect.minX + 0.195 * rect.width, y: rect.minY + 0.90 * rect.height)
    g.drawRadialGradient(gradient([(0, rgb(0x9B6BFF, 0.45)), (1, rgb(0x9B6BFF, 0))]),
                         startCenter: c2, startRadius: 0, endCenter: c2, endRadius: 0.58 * rect.width, options: [])
    g.restoreGState()
}

/// Pre-Tahoe icon: baked squircle body (824 px in 1024), drop shadow, sheen and inner rim.
func drawClassicIcon(_ g: CGContext, variant: String) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)

    // Drop shadow (body filled once with shadow, then painted over)
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x000000, 0.38))
    g.addPath(shape); g.setFillColor(rgb(0x2A1B8A)); g.fillPath()
    g.restoreGState()

    g.saveGState()
    g.addPath(shape); g.clip()
    drawBackground(g, in: CGRect(x: 100, y: 100, width: 824, height: 824))
    drawGlyph(g, variant: variant)

    // Liquid-glass sheen: soft top highlight fading out (no hard edge)
    g.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.28)), (0.55, rgb(0xFFFFFF, 0.06)), (1, rgb(0xFFFFFF, 0))]),
                         start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 470), options: [])

    // Inner rim light: bright at top, fading down, plus a thin cyan rim at the bottom
    g.addPath(shape); g.setLineWidth(10)
    g.replacePathWithStrokedPath(); g.clip()
    g.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.75)), (0.35, rgb(0xFFFFFF, 0.18)), (0.75, rgb(0xFFFFFF, 0.05)), (1, rgb(0x7DF0FF, 0.45))]),
                         start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    g.restoreGState()
}

/// Square, opaque, unmasked artwork: what Tahoe expects (it applies its own mask, shadow and highlights).
func drawFullBleedIcon(_ g: CGContext, variant: String) {
    drawBackground(g, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    glowAlpha = 0.45
    drawCenteredGlyph(g, variant: variant)
    glowAlpha = 0.85
}

/// Full-bleed artwork clipped to a squircle (824 px body in a 1024 canvas) with a soft shadow; for README images.
func drawMaskedIcon(_ g: CGContext, variant: String) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: rgb(0x000000, 0.30))
    g.addPath(shape); g.setFillColor(rgb(0x2A1B8A)); g.fillPath()
    g.restoreGState()
    g.saveGState()
    g.addPath(shape); g.clip()
    g.translateBy(x: 100, y: 100)
    g.scaleBy(x: 824 / canvas, y: 824 / canvas)
    drawFullBleedIcon(g, variant: variant)
    g.restoreGState()
}

func drawIcon(_ g: CGContext, variant: String, style: Style) {
    switch style {
    case .fullbleed: drawFullBleedIcon(g, variant: variant)
    case .masked: drawMaskedIcon(g, variant: variant)
    case .classic: drawClassicIcon(g, variant: variant)
    }
}

/// Glyph only on a transparent canvas (foreground layer of the Icon Composer package).
func drawGlyphLayer(_ g: CGContext, variant: String) {
    glowAlpha = 0
    drawCenteredGlyph(g, variant: variant)
    glowAlpha = 0.85
}

func makeContext(size: Int, opaque: Bool) -> CGContext {
    let g = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    g.interpolationQuality = .high
    g.setShouldAntialias(true)
    g.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    return g
}

func render(size: Int, variant: String, style: Style) -> CGImage {
    let g = makeContext(size: size, opaque: style == .fullbleed)
    drawIcon(g, variant: variant, style: style)
    return g.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot finalize \(url.path)") }
}

// MARK: - CLI

var args = CommandLine.arguments
var style = Style.fullbleed
if let i = args.firstIndex(of: "--style") {
    guard i + 1 < args.count, let st = Style(rawValue: args[i + 1]) else { print("--style needs fullbleed|masked|classic"); exit(1) }
    style = st
    args.removeSubrange(i...(i + 1))
}
guard args.count >= 4 else {
    print("usage: icongen preview <a|b|c> <out.png> | appiconset <a|b|c> <dir> [docs/icon-1024.png] | iconlayers <a|b|c> <AppIcon.icon dir>  [--style fullbleed|masked|classic]")
    exit(1)
}
let variant = args[2]
switch args[1] {
case "preview":
    writePNG(render(size: 1024, variant: variant, style: style), to: URL(fileURLWithPath: args[3]))
case "appiconset":
    let dir = URL(fileURLWithPath: args[3])
    // (point size, scale)
    let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    var images: [[String: String]] = []
    for (pt, scale) in slots {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        writePNG(render(size: pt * scale, variant: variant, style: style), to: dir.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)"])
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: dir.appendingPathComponent("Contents.json"))
    // The README image is always the masked preview (the asset catalog itself stays full-bleed).
    if args.count >= 5 { writePNG(render(size: 1024, variant: variant, style: style == .fullbleed ? .masked : style), to: URL(fileURLWithPath: args[4])) }
case "iconlayers":
    let dir = URL(fileURLWithPath: args[3])
    let bg = makeContext(size: 1024, opaque: true)
    drawBackground(bg, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    writePNG(bg.makeImage()!, to: dir.appendingPathComponent("Assets/background.png"))
    let fg = makeContext(size: 1024, opaque: false)
    drawGlyphLayer(fg, variant: variant)
    writePNG(fg.makeImage()!, to: dir.appendingPathComponent("Assets/glyph.png"))
    let json = """
    {
      "groups" : [
        {
          "layers" : [
            { "image-name" : "glyph.png", "name" : "glyph" }
          ],
          "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
          "translucency" : { "enabled" : true, "value" : 0.4 }
        },
        {
          "layers" : [
            { "image-name" : "background.png", "name" : "background" }
          ]
        }
      ],
      "supported-platforms" : { "circles" : ["watchOS"], "squares" : "shared" }
    }
    """
    try json.write(to: dir.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
default:
    print("unknown command \(args[1])"); exit(1)
}
