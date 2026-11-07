import SwiftUI

/// Metrik panellerinin ortak iskeleti: başlık (simge + ad + "Birleşik görünüm" + dişli), yüksekliği sınırlı kaydırılan gövde,
/// sabit alt bilgi. Gövde ekran sınırını aşarsa kaydırılır; başlık ve alt bilgi her zaman görünür kalır.
struct PanelScaffold<Content: View, Footer: View>: View {
    static var width: CGFloat { PanelContent.width }
    private static var padding: CGFloat { 14 }
    
    let kind: PanelKind
    let actions: PanelActions
    let opensMainWindow: Bool
    var subtitle: String?
    /// Kartlar arası boşluk (pil paneli daha sıkı).
    var spacing: CGFloat = 10
    /// Açılışta kaydırılıp ortalanacak öğe kimliği (ör. menü çubuğundaki cihaz öğesine tıklanınca).
    var scrollTarget: String?
    /// nil ise sınırsız (önizleme/test).
    var maxHeight: CGFloat?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @State private var bodyHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            if maxHeight != nil {
                ScrollViewReader { proxy in
                    ScrollView {
                        bodyStack
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.automatic)
                    .frame(height: scrollHeight)
                    .task(id: scrollTarget) {
                        guard let scrollTarget else { return }
                        try? await Task.sleep(for: .milliseconds(120))
                        proxy.scrollTo(scrollTarget, anchor: .center)
                    }
                }
            } else {
                bodyStack
            }
            footer
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.panelDensity, .compact)
    }

    private var bodyStack: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrollHeight: CGFloat? {
        guard let maxHeight, bodyHeight > 0 else { return nil }
        let available = maxHeight - 2 * Self.padding - headerHeight - footerHeight - 2 * spacing
        return max(120, min(bodyHeight, available))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(kind.tint.gradient, in: .rect(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(kind.displayName).font(.headline).accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: actions.showCombined) {
                Label("Birleşik görünüm", systemImage: "square.grid.2x2")
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Tüm metrikleri tek panelde göster")
            Button(opensMainWindow ? "Adalmon'u aç" : "Ayarlar", systemImage: "gearshape", action: actions.openApp)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(opensMainWindow ? "Adalmon'u aç" : "Ayarlar")
        }
        .frame(minHeight: 26)
    }
}

/// Alt bilgi düğmesi (ör. "Süreçler'de aç").
struct PanelFooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage).font(.callout)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background { PanelCardBackground(cornerRadius: 12) }
            .contentShape(.rect(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
