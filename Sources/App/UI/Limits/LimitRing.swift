import SwiftUI

/// Ton → renk. Normal kullanım vurgu rengi, uyarı turuncu, kritik kırmızı; bayat/yenilenmiş soluk.
enum LimitStyle {
    static func color(_ tone: LimitTone) -> Color {
        switch tone {
        case .normal: .accentColor
        case .warning: .orange
        case .critical: .red
        case .muted: .secondary
        }
    }
}

/// Dairesel gösterge. Pil kuralı: sürekli animasyon yok; dolum yalnızca ilk görünüşte (bir kez) ve değer değişince yumuşakça animasyonlanır.
/// "Hareketi azalt" açıkken animasyon yapılmaz.
struct LimitRing: View {
    let fraction: Double
    let tone: LimitTone
    var diameter: CGFloat = 40
    var lineWidth: CGFloat = 5
    /// Halkanın ortasındaki metin (ör. "62"); nil = boş.
    var label: String?
    var labelFont: Font = .system(size: 11, weight: .semibold, design: .rounded)
    /// Eşik işaretleri (0...1): halka üzerinde ince çentik.
    var markers: [Double] = []
    /// false: ilk görünüşte dolum animasyonu yok (önizleme/test).
    var entrance = true

    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(fraction: Double, tone: LimitTone, diameter: CGFloat = 40, lineWidth: CGFloat = 5, label: String? = nil,
         labelFont: Font = .system(size: 11, weight: .semibold, design: .rounded), markers: [Double] = [], entrance: Bool = true) {
        self.fraction = fraction
        self.tone = tone
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.label = label
        self.labelFont = labelFont
        self.markers = markers
        self.entrance = entrance
        _shown = State(initialValue: !entrance)
    }

    var body: some View {
        let color = LimitStyle.color(tone)
        let value = min(1, max(0, fraction))
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown ? max(value, value > 0 ? 0.004 : 0) : 0)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: value)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: tone)
            ForEach(markers, id: \.self) { marker in
                Circle()
                    .trim(from: max(0, marker - 0.004), to: min(1, marker + 0.004))
                    .stroke(Color.primary.opacity(0.5), style: StrokeStyle(lineWidth: lineWidth + 2, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            if let label {
                Text(label)
                    .font(labelFont)
                    .monospacedDigit()
                    .foregroundStyle(tone == .muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: label)
                    .padding(.horizontal, lineWidth + 1)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 0.9)) { shown = true } }
        }
        .accessibilityHidden(true)
    }
}

/// İnce yatay çubuk (geçen süre vb.); doluluk değişince yumuşak animasyon, ilk görünüşte bir kez dolar.
struct LimitBar: View {
    let fraction: Double
    var tint: Color = .secondary
    var height: CGFloat = 4
    var entrance = true

    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(fraction: Double, tint: Color = .secondary, height: CGFloat = 4, entrance: Bool = true) {
        self.fraction = fraction
        self.tint = tint
        self.height = height
        self.entrance = entrance
        _shown = State(initialValue: !entrance)
    }

    var body: some View {
        let value = shown ? min(1, max(0, fraction)) : 0
        Capsule()
            .fill(Color.primary.opacity(0.1))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(value > 0 ? height : 0, geo.size.width * value))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: value)
                }
            }
            .frame(height: height)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 0.9)) { shown = true } }
            }
            .accessibilityHidden(true)
    }
}
