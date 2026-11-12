import SwiftUI

/// 3D hissi veren bölüm illüstrasyonu: yumuşak parıltı, zemin gölgesi, arkada eğik plaka, önde ışıklı gradyan plaka ve simge.
/// `rotation3DEffect` ile hafif perspektif; görününce bir kez yerine oturur, imleç üstündeyken imlece doğru hafif eğilir.
/// Sürekli animasyon yoktur. "Hareketi azalt" açıkken sabit durur.
struct CleanupHeroArtwork: View {
    let symbol: String
    let accent: CleanupAccent
    /// Sağ üstte küçük rozet simgesi (isteğe bağlı).
    var badgeSymbol: String?
    var size: CGFloat = 148
    /// Görününce giriş animasyonu çalışsın mı (bir kez).
    var entrance = true

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cleanupStaticArtwork) private var staticArtwork
    @State private var settled = false
    @State private var tilt = CGSize.zero

    private var reduceMotion: Bool { systemReduceMotion || staticArtwork }

    var body: some View {
        let animated = !reduceMotion
        let entering = animated && entrance && !settled
        ZStack {
            // Parıltı ve zemin gölgesi: bulanıklık yerine radyal gradyan (ucuz, her yerde aynı çizilir).
            Circle()
                .fill(RadialGradient(colors: [accent.base.opacity(0.42), accent.base.opacity(0)],
                                     center: .center, startRadius: size * 0.1, endRadius: size * 0.62))
                .frame(width: size * 1.25, height: size * 1.25)
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.30), .black.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size * 0.34))
                .frame(width: size * 0.72, height: size * 0.16)
                .offset(y: size * 0.57)
            // Perspektif eğimi yalnızca girişte ve hover'da; "Hareketi azalt" açıkken düz çizim.
            if animated {
                plates
                    .rotation3DEffect(.degrees((entering ? -75 : 0) + Double(tilt.width) * 9), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                    .rotation3DEffect(.degrees(-Double(tilt.height) * 9), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
                    .scaleEffect(entering ? 0.7 : 1)
                    .opacity(entering ? 0 : 1)
            } else {
                plates
            }
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .contentShape(.rect)
        .onContinuousHover { phase in
            guard animated else { return }
            switch phase {
            case .active(let point):
                let side = size * 1.3
                // -1...1, 0,5'lik adımlara yuvarlanır (her piksel için yeniden çizim olmasın).
                func step(_ v: CGFloat) -> CGFloat { (min(1, max(-1, (v / side - 0.5) * 2)) * 2).rounded() / 2 }
                let next = CGSize(width: step(point.x), height: step(point.y))
                if next != tilt { withAnimation(.spring(duration: 0.3)) { tilt = next } }
            case .ended:
                if tilt != .zero { withAnimation(.spring(duration: 0.4)) { tilt = .zero } }
            }
        }
        .onAppear {
            guard animated, entrance, !settled else { settled = true; return }
            withAnimation(.spring(duration: 0.9, bounce: 0.28).delay(0.05)) { settled = true }
        }
        .accessibilityHidden(true)
    }

    private var plates: some View {
        let corner = size * 0.28
        let side = size * 0.74
        return ZStack {
            // Arka plaka: derinlik.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(accent.deep.opacity(0.75))
                .frame(width: side, height: side)
                .rotationEffect(.degrees(-9))
                .offset(x: -size * 0.07, y: size * 0.07)
            // Ön plaka.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(accent.gradient)
                .frame(width: side, height: side)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08), .black.opacity(0.25)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                )
                .shadow(color: accent.deep.opacity(0.5), radius: size * 0.1, x: 0, y: size * 0.07)
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 3)
            if let badgeSymbol {
                Image(systemName: badgeSymbol)
                    .font(.system(size: size * 0.13, weight: .bold))
                    .foregroundStyle(accent.deep)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .offset(x: side * 0.4, y: -side * 0.4)
            }
        }
    }
}

/// Karşılama ekranı: ortada 3D illüstrasyon, başlık, tek cümle ve tek büyük birincil düğme. `accessory` küçük ikincil ayar içindir
/// (ör. "Klasör seç…"); ana ekranı kalabalıklaştırmamak için sade tutulmalıdır.
struct CleanupHero3D<Accessory: View>: View {
    let symbol: String
    let accent: CleanupAccent
    var badgeSymbol: String?
    let title: String
    let subtitle: String
    let primaryTitle: String
    var primarySymbol: String?
    let action: () -> Void
    private let accessory: Accessory

    init(symbol: String, accent: CleanupAccent, badgeSymbol: String? = nil, title: String, subtitle: String,
         primaryTitle: String, primarySymbol: String? = nil, action: @escaping () -> Void,
         @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.accent = accent
        self.badgeSymbol = badgeSymbol
        self.title = title
        self.subtitle = subtitle
        self.primaryTitle = primaryTitle
        self.primarySymbol = primarySymbol
        self.action = action
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            CleanupHeroArtwork(symbol: symbol, accent: accent, badgeSymbol: badgeSymbol)
            VStack(spacing: 8) {
                Text(title).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }
            Button(action: action) {
                if let primarySymbol {
                    Label(primaryTitle, systemImage: primarySymbol)
                } else {
                    Text(primaryTitle)
                }
            }
            .buttonStyle(CleanupPrimaryButtonStyle(accent: accent))
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
            accessory
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension CleanupHero3D where Accessory == EmptyView {
    init(symbol: String, accent: CleanupAccent, badgeSymbol: String? = nil, title: String, subtitle: String,
         primaryTitle: String, primarySymbol: String? = nil, action: @escaping () -> Void) {
        self.init(symbol: symbol, accent: accent, badgeSymbol: badgeSymbol, title: title, subtitle: subtitle,
                  primaryTitle: primaryTitle, primarySymbol: primarySymbol, action: action) { EmptyView() }
    }
}
