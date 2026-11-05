import AppKit

/// Measures and draws the compact card layouts ("Tek satır", "Etiket üstte", "Simge").
/// Every width comes from the widest sample text of each value, summed unrounded and rounded once,
/// so the item is as narrow as possible and never changes width as values change.
enum CompactLayoutRenderer {
    static let labelGap: CGFloat = 2
    static let separatorPadding: CGFloat = 3
    static let separatorDot: CGFloat = 1.5
    static let columnGap: CGFloat = 3
    static let symbolBox: CGFloat = 13
    static let symbolGap: CGFloat = 2
    static let rowSymbolBox = CGSize(width: 7, height: 8)
    static let rowSymbolGap: CGFloat = 1.5
    private static let midY: CGFloat = 11
    private static let rowBaselines: [CGFloat] = [12.5, 2.5]

    // MARK: Shared helpers

    private struct Context {
        let component: MenuBarComponent
        let config: MenuBarConfig
        let values: WidgetValues

        var showUnits: Bool { config.showUnits }
        var labelColor: NSColor { WidgetPalette.label(opacity: config.clampedLabelOpacity) }

        func valueColor(_ field: DataField) -> NSColor {
            WidgetPalette.valueText(for: component, field: field, level: field.level(values), connection: values.connection)
        }

        func text(_ field: DataField, bare: Bool = false) -> String {
            field.compactText(values, showUnits: showUnits, unit: component.unit, bareTemperature: bare)
        }

        func widest(_ field: DataField, _ role: WidgetText.Role, bare: Bool = false) -> CGFloat {
            WidgetText.maxRawWidth(field.compactWidestTexts(values, showUnits: showUnits, unit: component.unit,
                                                            bareTemperature: bare), role)
        }
    }

    /// Per-row prefixes ("Simge"): network arrows as symbols, SSD/Pil as tiny text labels.
    private static func usesRowPrefixes(_ c: MenuBarComponent) -> Bool { c.showLabel && c.primary.needsOwnLabel }

    private static func rowPrefixWidth(_ field: DataField) -> CGFloat {
        field.category == .network ? rowSymbolBox.width : WidgetText.rawWidth(field.label, .miniLabel)
    }

    // MARK: Width

    static func width(of c: MenuBarComponent, config: MenuBarConfig, values: WidgetValues) -> CGFloat {
        let ctx = Context(component: c, config: config, values: values)
        let w: CGFloat = switch c.visual {
        case .labelAbove: labelAboveColumns(ctx).reduce(0) { $0 + $1.width } + columnGap * CGFloat(c.fields.count - 1)
        case .symbolStack: symbolLayout(ctx).total
        default: inlineWidth(ctx)
        }
        return ceil(w)
    }

    private static func inlineWidth(_ ctx: Context) -> CGFloat {
        let c = ctx.component
        var w: CGFloat = 0
        if c.showLabel, !c.primary.needsOwnLabel { w += WidgetText.rawWidth(c.primary.groupLabel, .compactLabel) + labelGap }
        for field in c.fields {
            if c.showLabel, field.needsOwnLabel { w += WidgetText.rawWidth(field.label, .compactLabel) + labelGap }
            w += ctx.widest(field, .compactValue)
        }
        return w + CGFloat(c.fields.count - 1) * (separatorPadding * 2 + separatorDot)
    }

    private struct Column {
        let field: DataField
        let label: String?
        let width: CGFloat
    }

    private static func labelAboveColumns(_ ctx: Context) -> [Column] {
        let c = ctx.component
        return c.fields.enumerated().map { i, field in
            let label = c.showLabel ? field.columnLabel(isFirst: i == 0) : nil
            let value = ctx.widest(field, .miniValue, bare: c.showLabel)
            return Column(field: field, label: label, width: max(value, label.map { WidgetText.rawWidth($0, .miniLabel) } ?? 0))
        }
    }

    private struct SymbolLayout {
        var lead: CGFloat
        var prefix: CGFloat
        var columns: [(fields: [DataField], width: CGFloat)]
        var total: CGFloat {
            lead + prefix + columns.reduce(0) { $0 + $1.width } + CGFloat(max(0, columns.count - 1)) * columnGap
        }
    }

    private static func symbolLayout(_ ctx: Context) -> SymbolLayout {
        let c = ctx.component
        let rows = usesRowPrefixes(c)
        let lead = c.showLabel && !rows ? symbolBox + symbolGap : 0
        let fields = c.fields
        if fields.count == 1 && !rows {
            return SymbolLayout(lead: lead, prefix: 0, columns: [(fields, ctx.widest(fields[0], .compactValue))])
        }
        let prefix = rows ? (fields.prefix(2).map(rowPrefixWidth).max() ?? 0) + rowSymbolGap : 0
        let chunks = stride(from: 0, to: fields.count, by: 2).map { Array(fields[$0..<min($0 + 2, fields.count)]) }
        let columns = chunks.map { chunk in (chunk, chunk.map { ctx.widest($0, .stackValue) }.max() ?? 0) }
        return SymbolLayout(lead: lead, prefix: prefix, columns: columns)
    }

    // MARK: Drawing

    static func draw(_ c: MenuBarComponent, config: MenuBarConfig, values: WidgetValues, in rect: CGRect) {
        let ctx = Context(component: c, config: config, values: values)
        switch c.visual {
        case .labelAbove: drawLabelAbove(ctx, rect)
        case .symbolStack: drawSymbol(ctx, rect)
        default: drawInline(ctx, rect)
        }
    }

    private static func drawInline(_ ctx: Context, _ rect: CGRect) {
        let c = ctx.component
        let labelBaseline = WidgetText.centeredBaseline(.compactLabel, midY: midY)
        let valueBaseline = WidgetText.centeredBaseline(.compactValue, midY: midY)
        var x = rect.minX
        func label(_ text: String) {
            let w = WidgetText.rawWidth(text, .compactLabel)
            WidgetText.draw(text, .compactLabel, color: ctx.labelColor, x: x, width: w, baseline: labelBaseline)
            x += w + labelGap
        }
        if c.showLabel, !c.primary.needsOwnLabel { label(c.primary.groupLabel) }
        for (i, field) in c.fields.enumerated() {
            if i > 0 {
                x += separatorPadding
                WidgetGraphics.dot(in: CGRect(x: x, y: midY - separatorDot / 2, width: separatorDot, height: separatorDot),
                                   color: ctx.labelColor)
                x += separatorDot + separatorPadding
            }
            if c.showLabel, field.needsOwnLabel { label(field.label) }
            // Every value but the last has its fixed widest-sample column (right-aligned), so separators and later
            // values never move; the last value follows its separator and its slack trails into the item spacing.
            let text = ctx.text(field)
            let isLast = i == c.fields.count - 1
            let w = isLast ? WidgetText.rawWidth(text, .compactValue) : ctx.widest(field, .compactValue)
            WidgetText.draw(text, .compactValue, color: ctx.valueColor(field), x: x, width: w, baseline: valueBaseline,
                            alignment: isLast ? .left : .right)
            x += w
        }
    }

    private static func drawLabelAbove(_ ctx: Context, _ rect: CGRect) {
        var x = rect.minX
        for column in labelAboveColumns(ctx) {
            if let label = column.label {
                WidgetText.draw(label, .miniLabel, color: ctx.labelColor, x: x, width: column.width, baseline: 13.5, alignment: .center)
            }
            let baseline = column.label == nil ? WidgetText.centeredBaseline(.miniValue, midY: midY) : 2.5
            WidgetText.draw(ctx.text(column.field, bare: column.label != nil), .miniValue, color: ctx.valueColor(column.field),
                            x: x, width: column.width, baseline: baseline, alignment: .center)
            x += column.width + columnGap
        }
    }

    private static func drawSymbol(_ ctx: Context, _ rect: CGRect) {
        let c = ctx.component
        let layout = symbolLayout(ctx)
        var x = rect.minX
        if layout.lead > 0 {
            WidgetGraphics.symbol(c.primary.compactSymbol,
                                  in: CGRect(x: x, y: midY - symbolBox / 2, width: symbolBox, height: symbolBox), color: ctx.labelColor)
            x += layout.lead
        }
        if layout.columns.count == 1, layout.columns[0].fields.count == 1, layout.prefix == 0 {
            let field = layout.columns[0].fields[0]
            WidgetText.draw(ctx.text(field), .compactValue, color: ctx.valueColor(field), x: x, width: layout.columns[0].width,
                            baseline: WidgetText.centeredBaseline(.compactValue, midY: midY), alignment: .right)
            return
        }
        if layout.prefix > 0 {
            for (field, baseline) in zip(c.fields.prefix(2), rowBaselines) {
                if field.category == .network {
                    let box = rowSymbolBox
                    WidgetGraphics.symbol(field.compactSymbol, in: CGRect(x: x, y: baseline - 0.5, width: box.width, height: box.height),
                                          color: ctx.labelColor)
                } else {
                    WidgetText.draw(field.label, .miniLabel, color: ctx.labelColor, x: x, width: layout.prefix, baseline: baseline + 0.5)
                }
            }
            x += layout.prefix
        }
        for column in layout.columns {
            let baselines = column.fields.count == 1 ? [WidgetText.centeredBaseline(.stackValue, midY: midY)] : rowBaselines
            for (field, baseline) in zip(column.fields, baselines) {
                WidgetText.draw(ctx.text(field), .stackValue, color: ctx.valueColor(field), x: x, width: column.width,
                                baseline: baseline, alignment: .right)
            }
            x += column.width + columnGap
        }
    }
}
