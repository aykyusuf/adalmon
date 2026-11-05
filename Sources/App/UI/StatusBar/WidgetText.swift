import AppKit
import CoreText

/// Menü çubuğu metin çizimi: sabit taban çizgisi, ölçüm ve yazı tipleri.
enum WidgetText {
    enum Role {
        /// Tek satır metin değeri.
        case value
        /// Küçük üst etiket.
        case label
        /// Etiket + değer stilinde değer.
        case stackedValue
        /// İki satır hız.
        case speed
        /// Tek satır hız.
        case speedOneLine
        /// Halka/çubuk/grafik yanındaki küçük değer.
        case small
        /// Yatay çubuk üstündeki metin.
        case barCaption
        /// Kompakt düzenler: "Tek satır" etiketi (9 pt, dar).
        case compactLabel
        /// "Tek satır" değeri (11 pt, dar, sabit rakam).
        case compactValue
        /// "Etiket üstte" üst etiketi (7,5 pt).
        case miniLabel
        /// "Etiket üstte" değeri (12 pt, dar, sabit rakam).
        case miniValue
        /// "Simge" iki satır değeri (10 pt, dar, sabit rakam).
        case stackValue
    }

    static func font(_ role: Role) -> NSFont {
        switch role {
        case .value: .monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        case .label: .systemFont(ofSize: 8, weight: .semibold)
        case .stackedValue: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        case .speed: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        case .speedOneLine: .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        case .small: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        case .barCaption: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        case .compactLabel: .systemFont(ofSize: 9, weight: .semibold, width: .condensed)
        case .compactValue: condensedDigits(11)
        case .miniLabel: .systemFont(ofSize: 7.5, weight: .semibold)
        case .miniValue: condensedDigits(12)
        case .stackValue: condensedDigits(10)
        }
    }

    /// SF condensed with monospaced digits: narrow, and values never jitter.
    private static func condensedDigits(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold, width: .condensed)
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Unrounded advance width; compact layouts sum these and round once.
    static func rawWidth(_ string: String, _ role: Role) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font(role)]).width
    }

    static func maxRawWidth(_ strings: [String], _ role: Role) -> CGFloat {
        strings.map { rawWidth($0, role) }.max() ?? 0
    }

    static func width(_ string: String, _ role: Role) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font(role)]).width)
    }

    static func maxWidth(_ strings: [String], _ role: Role) -> CGFloat {
        strings.map { width($0, role) }.max() ?? 0
    }

    /// Büyük harf yüksekliğini `midY` etrafında ortalayan taban çizgisi.
    static func centeredBaseline(_ role: Role, midY: CGFloat) -> CGFloat {
        (midY - font(role).capHeight / 2).rounded(.toNearestOrAwayFromZero)
    }

    enum Alignment { case left, center, right }

    /// `x...x+width` sütununa hizalı, verilen taban çizgisine metin çizer.
    static func draw(_ string: String, _ role: Role, color: NSColor, x: CGFloat, width: CGFloat,
                     baseline: CGFloat, alignment: Alignment = .left) {
        guard let ctx = NSGraphicsContext.current?.cgContext, !string.isEmpty else { return }
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font(role),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let originX: CGFloat = switch alignment {
        case .left: x
        case .center: x + (width - w) / 2
        case .right: x + width - w
        }
        ctx.saveGState()
        color.setFill()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: originX, y: baseline)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
