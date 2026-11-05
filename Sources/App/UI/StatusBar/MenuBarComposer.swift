import AppKit

enum MenuBarComposer {
    static let horizontalPadding: CGFloat = 1

    static func widths(of components: [MenuBarComponent], config: MenuBarConfig, values: WidgetValues) -> [CGFloat] {
        components.map { ComponentRenderer.width(of: $0, config: config, values: values) }
    }

    static func width(of components: [MenuBarComponent], config: MenuBarConfig, values: WidgetValues) -> CGFloat {
        guard !components.isEmpty else { return 0 }
        let content = widths(of: components, config: config, values: values).reduce(0, +)
        return content + CGFloat(components.count - 1) * config.clampedSpacing + horizontalPadding * 2
    }

    /// Horizontal slot of each component inside the composed image (unzoomed points), for hit testing.
    static func frames(of components: [MenuBarComponent], config: MenuBarConfig, values: WidgetValues) -> [ClosedRange<CGFloat>] {
        var x = horizontalPadding
        return widths(of: components, config: config, values: values).map { w in
            defer { x += w + config.clampedSpacing }
            return x...(x + w)
        }
    }

    static func image(for components: [MenuBarComponent], config: MenuBarConfig, values: WidgetValues,
                      appearance: NSAppearance.Name? = nil, zoom: CGFloat = 1) -> NSImage {
        let widths = widths(of: components, config: config, values: values)
        let size = NSSize(width: width(of: components, config: config, values: values) * zoom, height: ComponentRenderer.height * zoom)
        let spacing = config.clampedSpacing
        let image = NSImage(size: size, flipped: false) { _ in
            let draw = {
                if zoom != 1 { NSGraphicsContext.current?.cgContext.scaleBy(x: zoom, y: zoom) }
                var x = horizontalPadding
                for (component, w) in zip(components, widths) {
                    ComponentRenderer.draw(component, config: config, values: values,
                                           in: CGRect(x: x, y: 0, width: w, height: ComponentRenderer.height))
                    x += w + spacing
                }
            }
            if let appearance, let resolved = NSAppearance(named: appearance) {
                resolved.performAsCurrentDrawingAppearance(draw)
            } else {
                draw()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibilitySummary(for: components, values: values)
        return image
    }

    static func bitmap(_ image: NSImage, appearance: NSAppearance, scale: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * scale)),
                                         pixelsHigh: Int(ceil(size.height * scale)), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        out.isTemplate = image.isTemplate
        out.accessibilityDescription = image.accessibilityDescription
        return out
    }

    /// Hiç etkin widget yokken tıklanabilir kalması için sistem simgesi.
    static func placeholderImage() -> NSImage {
        let image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Adalmon") ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// VoiceOver ve ipucu için değer özeti: "Adalmon: CPU %46, Bellek %78, Ağ ↑ 1,2 MB/s ↓ 18,4 MB/s".
    static func accessibilitySummary(for components: [MenuBarComponent], values: WidgetValues) -> String {
        var seen = Set<String>()
        let parts = components.compactMap { c -> String? in
            let text = ComponentRenderer.spokenText(c, values: values)
            return seen.insert(text).inserted ? text : nil
        }
        return parts.isEmpty ? "Adalmon" : "Adalmon: " + parts.joined(separator: ", ")
    }
}
