import AppKit

/// Measures and draws one `MenuBarComponent` into a 22 pt tall menu bar slot.
/// Widths come only from the widest sample texts, so an item never changes width as values change.
enum ComponentRenderer {
    static let height: CGFloat = 22
    private static let midY: CGFloat = 11
    private static let gap: CGFloat = 3
    private static let labelValueGap: CGFloat = 3
    private static let twoLineBaselines: [CGFloat] = [12.5, 2.5]
    static let iconSize: CGFloat = 16

    /// What the text part of a component shows.
    private enum TextBlock {
        case none
        case single(label: String?, role: WidgetText.Role)
        case labelOver
        case twoLines(labels: Bool)
        case inline(labels: Bool)

        var isEmpty: Bool {
            if case .none = self { return true }
            return false
        }
    }

    private static let inlineSpacing: CGFloat = 6

    private static func textBlock(_ c: MenuBarComponent) -> TextBlock {
        switch c.visual {
        case .text:
            return c.secondary != nil ? .inline(labels: c.showLabel) : .single(label: c.showLabel ? c.primary.label : nil, role: .value)
        case .stacked2:
            return c.secondary != nil ? .twoLines(labels: c.showLabel) : .labelOver
        case .hbar, .dot, .oneLine, .labelAbove, .symbolStack:
            return .none
        case .iconValue, .bar, .ring, .sparkline:
            guard c.showValue else { return .none }
            if c.secondary != nil { return .twoLines(labels: c.showLabel) }
            return .single(label: nil, role: c.visual == .iconValue ? .value : .small)
        }
    }

    /// Leading label drawn before the graphic (single-field graphic visuals with the label on).
    private static func leadingLabel(_ c: MenuBarComponent) -> String? {
        guard c.showLabel, c.secondary == nil else { return nil }
        switch c.visual {
        case .iconValue, .bar, .ring, .sparkline: return c.primary.label
        default: return nil
        }
    }

    private static func graphicWidth(_ c: MenuBarComponent) -> CGFloat {
        switch c.visual {
        case .text, .stacked2, .hbar, .oneLine, .labelAbove, .symbolStack: 0
        case .iconValue: iconSize
        case .bar: WidgetGraphics.verticalBarSize.width
        case .ring: WidgetGraphics.ringDiameter
        case .sparkline: WidgetGraphics.sparklineSize.width
        case .dot: WidgetGraphics.dotDiameter
        }
    }

    // MARK: Width

    private static func widest(_ field: DataField, _ c: MenuBarComponent, _ config: MenuBarConfig,
                               _ values: WidgetValues, _ role: WidgetText.Role) -> CGFloat {
        WidgetText.maxWidth(field.widestTexts(values, showUnits: config.showUnits, unit: c.unit), role)
    }

    private struct TwoLineColumns {
        var label: CGFloat
        var value: CGFloat
        var total: CGFloat { label + value }
    }

    private static func twoLineColumns(_ c: MenuBarComponent, labels: Bool, config: MenuBarConfig,
                                       values: WidgetValues) -> TwoLineColumns {
        let fields = c.fields
        let label = labels ? (WidgetText.maxWidth(fields.map(\.label), .speed) + labelValueGap) : 0
        let value = fields.map { widest($0, c, config, values, .speed) }.max() ?? 0
        return TwoLineColumns(label: label, value: value)
    }

    private static func textBlockWidth(_ c: MenuBarComponent, _ block: TextBlock, config: MenuBarConfig,
                                       values: WidgetValues) -> CGFloat {
        switch block {
        case .none: 0
        case .single(let label, let role):
            (label.map { WidgetText.width($0, .label) + labelValueGap } ?? 0) + widest(c.primary, c, config, values, role)
        case .labelOver:
            max(WidgetText.width(c.primary.label, .label), widest(c.primary, c, config, values, .stackedValue))
        case .twoLines(let labels):
            twoLineColumns(c, labels: labels, config: config, values: values).total
        case .inline(let labels):
            c.fields.map { field in
                (labels ? WidgetText.width(field.label, .label) + labelValueGap : 0) + widest(field, c, config, values, .speedOneLine)
            }.reduce(0, +) + inlineSpacing * CGFloat(c.fields.count - 1)
        }
    }

    static func width(of c: MenuBarComponent, config: MenuBarConfig, values: WidgetValues) -> CGFloat {
        if c.visual.isCompact { return CompactLayoutRenderer.width(of: c, config: config, values: values) }
        let w: CGFloat
        switch c.visual {
        case .hbar:
            let label = c.showLabel ? WidgetText.width(c.primary.label, .label) + gap : 0
            let value = c.showValue ? widest(c.primary, c, config, values, .barCaption) : 0
            w = max(WidgetGraphics.horizontalBarMinWidth, label + value)
        case .dot:
            w = WidgetGraphics.dotDiameter
                + (c.showLabel ? gap + WidgetText.width(c.primary.label, .label) : 0)
                + (c.showValue && c.primary != .connection ? gap + widest(c.primary, c, config, values, .small) : 0)
        default:
            let block = textBlock(c)
            let lead = leadingLabel(c).map { WidgetText.width($0, .label) + gap } ?? 0
            let graphic = graphicWidth(c)
            let text = textBlockWidth(c, block, config: config, values: values)
            w = lead + graphic + (graphic > 0 && text > 0 ? gap : 0) + text
        }
        return ceil(w)
    }

    // MARK: Drawing

    static func draw(_ c: MenuBarComponent, config: MenuBarConfig, values: WidgetValues, in rect: CGRect) {
        if c.visual.isCompact {
            CompactLayoutRenderer.draw(c, config: config, values: values, in: rect)
            return
        }
        let level = c.primary.level(values)
        let graphicColor = WidgetPalette.graphic(for: c, field: c.primary, level: level, connection: values.connection)
        let labelColor = WidgetPalette.label(opacity: config.clampedLabelOpacity)
        func valueColor(_ field: DataField) -> NSColor {
            WidgetPalette.valueText(for: c, field: field, level: field.level(values), connection: values.connection)
        }
        func text(_ field: DataField) -> String { field.text(values, showUnits: config.showUnits, unit: c.unit) }
        var x = rect.minX

        switch c.visual {
        case .hbar:
            WidgetGraphics.horizontalBar(in: CGRect(x: rect.minX, y: 3, width: rect.width, height: WidgetGraphics.horizontalBarHeight),
                                         fraction: level, color: graphicColor)
            if c.showLabel {
                WidgetText.draw(c.primary.label, .label, color: labelColor, x: rect.minX, width: rect.width, baseline: 11.5)
            }
            if c.showValue {
                WidgetText.draw(text(c.primary), .barCaption, color: valueColor(c.primary), x: rect.minX, width: rect.width,
                                baseline: 11.5, alignment: c.showLabel ? .right : .center)
            }
            return
        case .dot:
            let d = WidgetGraphics.dotDiameter
            WidgetGraphics.dot(in: CGRect(x: x, y: midY - d / 2, width: d, height: d), color: graphicColor)
            x += d + gap
            if c.showLabel {
                let w = WidgetText.width(c.primary.label, .label)
                WidgetText.draw(c.primary.label, .label, color: labelColor, x: x, width: w,
                                baseline: WidgetText.centeredBaseline(.label, midY: midY))
                x += w + gap
            }
            if c.showValue && c.primary != .connection {
                WidgetText.draw(text(c.primary), .small, color: valueColor(c.primary), x: x, width: rect.maxX - x,
                                baseline: WidgetText.centeredBaseline(.small, midY: midY))
            }
            return
        default:
            break
        }

        if let label = leadingLabel(c) {
            let w = WidgetText.width(label, .label)
            WidgetText.draw(label, .label, color: labelColor, x: x, width: w, baseline: WidgetText.centeredBaseline(.label, midY: midY))
            x += w + gap
        }

        let gw = graphicWidth(c)
        switch c.visual {
        case .iconValue:
            let color = c.colorMode == .monochrome && c.primary != .connection ? NSColor.labelColor : graphicColor
            WidgetGraphics.symbol(c.primary.symbolName(values), in: CGRect(x: x, y: midY - iconSize / 2, width: iconSize, height: iconSize),
                                  color: color)
        case .bar:
            let size = WidgetGraphics.verticalBarSize
            WidgetGraphics.verticalBar(in: CGRect(x: x, y: midY - size.height / 2, width: size.width, height: size.height),
                                       fraction: level, color: graphicColor)
        case .ring:
            let d = WidgetGraphics.ringDiameter
            WidgetGraphics.ring(in: CGRect(x: x, y: midY - d / 2, width: d, height: d), fraction: level, color: graphicColor)
        case .sparkline:
            let size = WidgetGraphics.sparklineSize
            let r = CGRect(x: x, y: midY - size.height / 2, width: size.width, height: size.height)
            let history = c.primary.history(values)
            if let secondary = c.secondary, secondary.hasHistory, !secondary.historyIsNormalized, !c.primary.historyIsNormalized {
                let secondColor = WidgetPalette.graphic(for: c, field: secondary, level: secondary.level(values), connection: values.connection)
                WidgetGraphics.networkChart(in: r, up: secondary.history(values), down: history,
                                            upColor: secondColor, downColor: graphicColor)
            } else {
                WidgetGraphics.sparkline(in: r, values: history.isEmpty ? [level, level] : history,
                                         scale: c.primary.historyIsNormalized ? 1 : nil, color: graphicColor)
            }
        default:
            break
        }
        x += gw
        let block = textBlock(c)
        if gw > 0 && !block.isEmpty { x += gap }

        switch block {
        case .none:
            break
        case .single(let label, let role):
            if let label {
                let w = WidgetText.width(label, .label)
                WidgetText.draw(label, .label, color: labelColor, x: x, width: w, baseline: WidgetText.centeredBaseline(.label, midY: midY))
                x += w + labelValueGap
            }
            let alignment: WidgetText.Alignment = gw > 0 && c.visual != .iconValue ? .left : .right
            WidgetText.draw(text(c.primary), role, color: valueColor(c.primary), x: x, width: rect.maxX - x,
                            baseline: WidgetText.centeredBaseline(role, midY: midY), alignment: alignment)
        case .labelOver:
            WidgetText.draw(c.primary.label, .label, color: labelColor, x: x, width: rect.maxX - x, baseline: 13, alignment: .center)
            WidgetText.draw(text(c.primary), .stackedValue, color: valueColor(c.primary), x: x, width: rect.maxX - x,
                            baseline: 2.5, alignment: .center)
        case .twoLines(let labels):
            let cols = twoLineColumns(c, labels: labels, config: config, values: values)
            for (field, baseline) in zip(c.fields, twoLineBaselines) {
                if labels {
                    WidgetText.draw(field.label, .speed, color: labelColor, x: x, width: cols.label, baseline: baseline)
                }
                WidgetText.draw(text(field), .speed, color: valueColor(field), x: x + cols.label, width: cols.value,
                                baseline: baseline, alignment: .right)
            }
        case .inline(let labels):
            for field in c.fields {
                if labels {
                    let w = WidgetText.width(field.label, .label)
                    WidgetText.draw(field.label, .label, color: labelColor, x: x, width: w,
                                    baseline: WidgetText.centeredBaseline(.label, midY: midY))
                    x += w + labelValueGap
                }
                let w = widest(field, c, config, values, .speedOneLine)
                WidgetText.draw(text(field), .speedOneLine, color: valueColor(field), x: x, width: w,
                                baseline: WidgetText.centeredBaseline(.speedOneLine, midY: midY), alignment: .right)
                x += w + inlineSpacing
            }
        }
    }

    // MARK: Accessibility

    static func spokenText(_ c: MenuBarComponent, values: WidgetValues) -> String {
        c.fields.map { field in
            field == .connection
                ? "Bağlantı " + (values.connection == .offline ? "yok" : field.text(values, showUnits: true))
                : field.displayName + " " + field.text(values, showUnits: true, unit: c.unit)
        }.joined(separator: ", ")
    }
}
