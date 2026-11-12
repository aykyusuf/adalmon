import SwiftUI

/// Temizlik bitti kutlaması: onay simgeli 3D illüstrasyon, bir kerelik kıvılcım patlaması, sayarak yükselen "X GB boşaltıldı".
/// Animasyon yalnızca görününce bir kez çalışır; "Hareketi azalt" açıkken yoktur.
struct CleanupDoneView: View {
    let accent: CleanupAccent
    let bytes: UInt64
    /// Rakamın altındaki cümle ("boşaltıldı", "Çöp Sepeti'ne taşındı").
    var headline = "boşaltıldı"
    var detail: String?
    var primaryTitle = "Yeniden tara"
    var primarySymbol = "arrow.clockwise"
    var secondaryTitle: String?
    var onSecondary: (() -> Void)?
    let onPrimary: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cleanupStaticArtwork) private var staticArtwork
    @State private var shownBytes: UInt64 = 0
    @State private var burst = false

    private static let particleCount = 14
    private var reduceMotion: Bool { systemReduceMotion || staticArtwork }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            ZStack {
                ForEach(0..<Self.particleCount, id: \.self) { index in particle(index) }
                CleanupHeroArtwork(symbol: "checkmark", accent: accent, size: 132)
            }
            VStack(spacing: 4) {
                Text(Format.bytes(shownBytes))
                    .font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [accent.light, accent.deep], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText(value: Double(shownBytes)))
                Text(headline).font(.title2).foregroundStyle(.secondary)
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 460).padding(.top, 4)
                }
            }
            HStack(spacing: 12) {
                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle, action: onSecondary).controlSize(.large)
                }
                Button(action: onPrimary) { Label(primaryTitle, systemImage: primarySymbol) }
                    .buttonStyle(CleanupPrimaryButtonStyle(accent: accent))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .onAppear {
            guard !reduceMotion else {
                shownBytes = bytes
                burst = true
                return
            }
            withAnimation(.easeOut(duration: 0.9).delay(0.25)) { shownBytes = bytes }
            withAnimation(.easeOut(duration: 1.0).delay(0.15)) { burst = true }
        }
        .onChange(of: bytes) { _, new in shownBytes = new }
    }

    /// Bir kerelik kıvılcım: merkezden dışa açılıp solar.
    private func particle(_ index: Int) -> some View {
        let angle = Double(index) / Double(Self.particleCount) * 2 * .pi
        let distance: CGFloat = index.isMultiple(of: 2) ? 112 : 88
        let size: CGFloat = index.isMultiple(of: 3) ? 9 : 6
        return Circle()
            .fill(index.isMultiple(of: 2) ? accent.light : accent.deep)
            .frame(width: size, height: size)
            .offset(x: burst ? cos(angle) * distance : 0, y: burst ? sin(angle) * distance : 0)
            .scaleEffect(burst ? 0.3 : 1)
            .opacity(burst ? 0 : (reduceMotion ? 0 : 1))
            .accessibilityHidden(true)
    }
}

/// Boş sonuç: "Her şey temiz".
struct CleanupAllCleanView: View {
    let accent: CleanupAccent
    var title = "Her şey temiz"
    let subtitle: String
    var primaryTitle: String?
    var primarySymbol = "arrow.clockwise"
    var onPrimary: (() -> Void)?
    /// Sayfa içinde başka içerikle (ör. incele kartları) yan yana kullanırken yer kazanmak için.
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 10 : 16) {
            if !compact { Spacer(minLength: 0) }
            CleanupHeroArtwork(symbol: "checkmark.seal.fill", accent: accent, badgeSymbol: "sparkles", size: compact ? 96 : 132)
            VStack(spacing: 6) {
                Text(title).font(compact ? .title.weight(.bold) : .largeTitle.weight(.bold))
                Text(subtitle).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 460)
            }
            if let primaryTitle, let onPrimary {
                Button(action: onPrimary) { Label(primaryTitle, systemImage: primarySymbol) }
                    .buttonStyle(CleanupPrimaryButtonStyle(accent: accent, prominent: !compact))
                    .keyboardShortcut(.defaultAction)
            }
            if !compact { Spacer(minLength: 0) }
        }
        .padding(compact ? 12 : 24)
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity)
    }
}
