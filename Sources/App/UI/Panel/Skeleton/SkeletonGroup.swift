import SwiftUI

/// İskelet satırlarını saran kap: içerik soluk bloklardan oluşur; üzerinden tek bir ışık bandı geçer (parıltı).
/// Hareketi azalt açıkken parıltı yoktur, bloklar durağan kalır. Erişilebilirlik için tek "Yükleniyor" öğesi.
struct SkeletonGroup<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        let width = geo.size.width
                        LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(40, width * 0.45))
                            .offset(x: -width * 0.45 + (width * 1.45) * phase)
                    }
                    .mask { content }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) { phase = 1 }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Yükleniyor")
    }
}

extension View {
    /// İskelet bloğu: metnin yerini tutan soluk yuvarlak dikdörtgen (satır yüksekliği gerçek metinle aynı kalır).
    func skeletonBlock(cornerRadius: CGFloat = 4) -> some View {
        foregroundStyle(.clear)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.primary.opacity(0.13)))
    }
}

/// Listelerde iskelet ↔ gerçek satır geçişi. İçerikler aynı yüksekliktedir (iskelet gerçek satırın yerleşimini kullanır).
struct SkeletonSwap<Loaded: View, Placeholder: View>: View {
    let isLoading: Bool
    @ViewBuilder var loaded: Loaded
    @ViewBuilder var placeholder: Placeholder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if isLoading {
                SkeletonGroup { placeholder }.transition(.opacity)
            } else {
                loaded.transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isLoading)
    }
}

extension View {
    /// İskeletin sonsuza dek kalmaması için: `ListLoadState.timeout` sn sonra `timedOut` true olur.
    func loadTimeout(_ timedOut: Binding<Bool>) -> some View {
        task {
            try? await Task.sleep(for: .seconds(ListLoadState.timeout))
            if !Task.isCancelled { timedOut.wrappedValue = true }
        }
    }
}
