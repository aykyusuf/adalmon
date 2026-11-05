import AppKit

enum WidgetPalette {
    static let minimumTextAlpha: Double = 0.6

    static var track: NSColor { NSColor.labelColor.withAlphaComponent(0.22) }

    static func label(opacity: Double) -> NSColor {
        NSColor.labelColor.withAlphaComponent(max(minimumTextAlpha, min(1, opacity)))
    }

    static func threshold(_ level: ThresholdLevel) -> NSColor {
        switch level {
        case .normal: .systemGreen
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }

    static func connection(_ state: ConnectionState) -> NSColor {
        switch state {
        case .online: .systemGreen
        case .mobile: .systemOrange
        case .offline: .systemGray
        }
    }

    static func fixedColor(for component: MenuBarComponent, level: Double) -> RGBAColor? {
        switch component.colorMode {
        case .custom: component.customColor
        case .gradient: component.gradientStart.interpolated(to: component.gradientEnd, fraction: level)
        case .monochrome, .accent, .threshold: nil
        }
    }

    /// Color of the graphic (bar, ring, line, dot, icon) for a field at `level`.
    static func fill(for component: MenuBarComponent, field: DataField, level: Double, connection: ConnectionState) -> NSColor {
        if field == .connection { return self.connection(connection) }
        if let rgba = fixedColor(for: component, level: level) { return rgba.nsColor }
        switch component.colorMode {
        case .accent: return .controlAccentColor
        case .threshold:
            // A card can mix kinds (CPU % and °C): other kinds use their own default thresholds.
            let thresholds = field.kind == component.primary.kind ? component.thresholds : field.defaultThresholds
            return threshold(thresholds.level(for: level))
        default: return .labelColor
        }
    }

    /// Whether value text is colored: always for text-only visuals, otherwise per `colorTarget`.
    static func colorsValue(_ component: MenuBarComponent) -> Bool {
        guard component.colorMode != .monochrome else { return false }
        return component.colorTarget != .visual || !component.visual.hasGraphic
    }

    static func colorsGraphic(_ component: MenuBarComponent) -> Bool {
        component.colorTarget != .value
    }

    static func valueText(for component: MenuBarComponent, field: DataField, level: Double,
                          connection: ConnectionState) -> NSColor {
        guard colorsValue(component) else { return .labelColor }
        if field != .connection, var rgba = fixedColor(for: component, level: level) {
            rgba.alpha = max(minimumTextAlpha, rgba.alpha)
            return rgba.nsColor
        }
        return fill(for: component, field: field, level: level, connection: connection)
    }

    static func graphic(for component: MenuBarComponent, field: DataField, level: Double,
                        connection: ConnectionState) -> NSColor {
        if field == .connection { return self.connection(connection) }
        guard colorsGraphic(component) else { return .labelColor }
        return fill(for: component, field: field, level: level, connection: connection)
    }
}
