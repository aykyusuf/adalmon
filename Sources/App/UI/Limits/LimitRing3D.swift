import SwiftUI

/// Marka tonları (Limitler sayfası): kart rengi ve halkanın normal rengi. Uyarı turuncu, kritik kırmızı kalır.
enum LimitBrand {
    static func color(_ source: LimitSource) -> Color {
        switch source {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.06, green: 0.64, blue: 0.50)
        }
    }

    static func ringColor(_ tone: LimitTone, source: LimitSource) -> Color {
        tone == .normal ? color(source) : LimitStyle.color(tone)
    }
}

/// Derinlik hissi veren halka: yerdeki gölge, cam plaka, oluk, kalınlık veren istiflenmiş yaylar, parlak üst yüz ve ortada sayı.
/// Katmanlar `limitTilt` ile farklı hızda kayar (parallax); `Tilt3D` içinde değilse düz durur. Sürekli animasyon yok:
/// dolum ilk görünüşte bir kez ve değer değişince animasyonlanır.
struct LimitRing3D: View {
    let fraction: Double
    let tone: LimitTone
    let source: LimitSource
    var diameter: CGFloat = 132
    var lineWidth: CGFloat = 14
    var label: String
    var caption: String?
    var markers: [Double] = []
    /// false: ilk görünüşte dolum animasyonu yok (önizleme/test).
    var entrance = true
    /// Dolumun başlama gecikmesi (kartlar sırayla dolsun).
    var delay: Double = 0

    @State private var shown: Bool
    @Environment(\.limitTilt) private var tilt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    init(fraction: Double, tone: LimitTone, source: LimitSource, diameter: CGFloat = 132, lineWidth: CGFloat = 14, label: String,
         caption: String? = nil, markers: [Double] = [], entrance: Bool = true, delay: Double = 0) {
        self.fraction = fraction
        self.tone = tone
        self.source = source
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.label = label
        self.caption = caption
        self.markers = markers
        self.entrance = entrance
        self.delay = delay
        _shown = State(initialValue: !entrance)
    }

    private static let layers = 7

    var body: some View {
        let color = LimitBrand.ringColor(tone, source: source)
        let value = shown ? min(1, max(0, fraction)) : 0
        let trimEnd = value > 0 ? max(value, 0.006) : 0
        let muted = tone == .muted
        ZStack {
            // Yerdeki gölge: imleçle ters yöne kayar.
            Ellipse()
                .fill(.black.opacity(scheme == .dark ? 0.5 : 0.22))
                .frame(width: diameter * 0.72, height: diameter * 0.14)
                .blur(radius: 9)
                .offset(x: -tilt.width * 10, y: diameter * 0.62 - tilt.height * 4)
            // Cam plaka.
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.12 : 0.55), .white.opacity(scheme == .dark ? 0.02 : 0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(.white.opacity(scheme == .dark ? 0.18 : 0.7), lineWidth: 1))
                .padding(-lineWidth * 0.55)
                .offset(x: tilt.width * 2, y: tilt.height * 2)
            // Oluk.
            Circle()
                .stroke(Color.primary.opacity(scheme == .dark ? 0.16 : 0.1), lineWidth: lineWidth)
            // Kalınlık: koyu tonlu istiflenmiş yaylar; imleçle birlikte kayarak yan yüzü gösterir.
            ForEach(1...Self.layers, id: \.self) { index in
                arc(trimEnd: trimEnd)
                    .stroke(color.mix(with: .black, by: 0.42 - 0.03 * Double(index)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .offset(x: -tilt.width * 0.9 * Double(index), y: 1.0 * Double(index) - tilt.height * 0.9 * Double(index))
            }
            // Üst yüz.
            arc(trimEnd: trimEnd)
                .stroke(AngularGradient(colors: [color.mix(with: .white, by: 0.28), color, color.mix(with: .black, by: 0.12)],
                                        center: .center, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * max(value, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            // Parlak çizgi.
            arc(trimEnd: trimEnd)
                .stroke(.white.opacity(muted ? 0.15 : 0.32), style: StrokeStyle(lineWidth: max(1.5, lineWidth * 0.2), lineCap: .round))
                .padding(lineWidth * 0.22)
            ForEach(markers, id: \.self) { marker in
                Circle()
                    .trim(from: max(0, marker - 0.004), to: min(1, marker + 0.004))
                    .stroke(Color.primary.opacity(0.55), style: StrokeStyle(lineWidth: lineWidth + 6, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: diameter * 0.26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: label)
                if let caption {
                    Text(caption).font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, lineWidth + 4)
            .offset(x: tilt.width * 5, y: tilt.height * 5)
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: value)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: tone)
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 1.0).delay(delay)) { shown = true } }
        }
        .accessibilityHidden(true)
    }

    private func arc(trimEnd: Double) -> some Shape {
        Circle().trim(from: 0, to: trimEnd).rotation(.degrees(-90))
    }
}
