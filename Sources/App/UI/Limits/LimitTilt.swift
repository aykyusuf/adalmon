import SwiftUI

/// İmleç konumu (-1...1, merkez 0,0). Tilt3D içindeki katmanlar bunu okuyup farklı derinliklerde kayarak parallax verir.
private struct LimitTiltKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

private struct LimitCardWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 560
}

extension EnvironmentValues {
    var limitTilt: CGSize {
        get { self[LimitTiltKey.self] }
        set { self[LimitTiltKey.self] = newValue }
    }

    /// Kahraman kartının dış genişliği (Limitler sayfası hesaplar). İç düzen (halka boyutu, tek/çift satır) buna göre
    /// belirlenir; `ViewThatFits` ile alternatifleri ölçmek yerine tek geçişte, belirlenimli.
    var limitCardWidth: CGFloat {
        get { self[LimitCardWidthKey.self] }
        set { self[LimitCardWidthKey.self] = newValue }
    }
}

/// Bir kartın iç düzeni: kart genişliğinden ve pencere sayısından türetilir.
struct LimitCardMetrics: Equatable {
    static let padding: CGFloat = 20
    static let cellGap: CGFloat = 14
    let inner: CGFloat
    let windowCount: Int

    init(cardWidth: CGFloat, windowCount: Int) {
        inner = max(120, cardWidth - 2 * Self.padding)
        self.windowCount = windowCount
    }

    /// Başlıkta rozetler ve tazelik tek satıra sığar mı?
    var headerOneRow: Bool { inner >= 440 }
    /// Model dağılımı başlığı (başlık + sekmeler) tek satıra sığar mı?
    var usageHeaderOneRow: Bool { inner - 28 >= 370 }
    /// Model satırında sayılar adın yanında mı, altında mı?
    var usageRowsInline: Bool { inner - 28 >= 400 }
    /// Pencere hücreleri yan yana mı (çok dar kartta alt alta)?
    var windowsSideBySide: Bool { windowCount < 2 || (inner - Self.cellGap) / 2 >= 118 }
    var cellWidth: CGFloat { windowCount > 1 && windowsSideBySide ? (inner - Self.cellGap) / 2 : inner }
    /// Halka çapı: hücreye sığar, 76...128.
    var ringDiameter: CGFloat { min(128, max(76, cellWidth - 28 - 18)) }
    var ringLine: CGFloat { (ringDiameter * 0.11).rounded() }
    var compactCell: Bool { cellWidth < 190 }
}

/// İmleç üzerindeyken perspektifli eğilme + ışık yansıması. Pil kuralı: yalnızca `onContinuousHover` sırasında durum değişir;
/// imleç ayrılınca yumuşakça sıfıra döner, sürekli animasyon yoktur. "Hareketi azalt" açıkken eğilme yapılmaz.
/// `fixed`: önizleme/test için sabit eğim (imleç gerekmez).
struct Tilt3D: ViewModifier {
    var maxDegrees: Double
    var perspective: CGFloat = 0.6
    var glossRadius: CGFloat = 260
    var glossOpacity: Double = 0.16
    var fixed: CGSize?

    @State private var pointer: CGSize = .zero
    @State private var size: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let tilt = reduceMotion ? CGSize.zero : (fixed ?? pointer)
        ZStack {
            content
                .environment(\.limitTilt, tilt)
                .overlay { if glossOpacity > 0 { gloss(tilt) } }
                .rotation3DEffect(.degrees(-tilt.height * maxDegrees), axis: (x: 1, y: 0, z: 0), perspective: perspective)
                .rotation3DEffect(.degrees(tilt.width * maxDegrees), axis: (x: 0, y: 1, z: 0), perspective: perspective)
                .animation(.smooth(duration: 0.2), value: tilt)
        }
        // Algılama dönmeyen dış çerçevede: dönen içeriğin kendi şekli imleç konumunu bozmaz.
        .contentShape(.rect)
        .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                guard size.width > 1, size.height > 1 else { return }
                pointer = CGSize(width: min(1, max(-1, (location.x / size.width - 0.5) * 2)),
                                 height: min(1, max(-1, (location.y / size.height - 0.5) * 2)))
            case .ended:
                pointer = .zero
            }
        }
    }

    /// İmleci izleyen yumuşak ışık; eğim yokken görünmez.
    @ViewBuilder private func gloss(_ tilt: CGSize) -> some View {
        let strength = min(1, (abs(tilt.width) + abs(tilt.height)) * 1.4)
        RadialGradient(colors: [.white.opacity(glossOpacity), .clear],
                       center: UnitPoint(x: 0.5 + tilt.width * 0.42, y: 0.5 + tilt.height * 0.42),
                       startRadius: 0, endRadius: glossRadius)
            .opacity(strength)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    func tilt3D(_ maxDegrees: Double, perspective: CGFloat = 0.6, glossRadius: CGFloat = 260, glossOpacity: Double = 0.16,
                fixed: CGSize? = nil) -> some View {
        modifier(Tilt3D(maxDegrees: maxDegrees, perspective: perspective, glossRadius: glossRadius, glossOpacity: glossOpacity,
                        fixed: fixed))
    }

    /// Kartın sırayla "yükselerek" girmesi: 3D dönüş + yükselme + belirme. `appeared` bir kez true olur (sayfa görününce).
    /// "Hareketi azalt" açıkken yalnızca anında görünür.
    func limitEntrance(_ appeared: Bool, index: Int) -> some View {
        modifier(LimitEntrance(appeared: appeared, index: index))
    }
}

private struct LimitEntrance: ViewModifier {
    let appeared: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(appeared || reduceMotion ? 0 : -24), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .offset(y: appeared || reduceMotion ? 0 : 26)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.62, dampingFraction: 0.82).delay(0.09 * Double(index)), value: appeared)
    }
}
