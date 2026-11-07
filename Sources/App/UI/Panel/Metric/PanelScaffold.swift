import SwiftUI

/// Metrik panellerinin ortak iskeleti: başlık (simge + ad + "Birleşik görünüm" + dişli), yüksekliği sınırlı kaydırılan gövde,
/// sabit alt bilgi. Gövde ekran sınırını aşarsa kaydırılır; başlık ve alt bilgi her zaman görünür kalır.
struct PanelScaffold<Content: View, Footer: View>: View {
    static var width: CGFloat { PanelContent.width }
    private static var padding: CGFloat { 14 }
    private static var spacing: CGFloat { 10 }

    let kind: PanelKind
    let actions: PanelActions
    let opensMainWindow: Bool
    var subtitle: String?
    /// nil ise sınırsız (önizleme/test).
    var maxHeight: CGFloat?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @State private var bodyHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            if maxHeight != nil {
                ScrollView {
                    bodyStack
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.automatic)
                .frame(height: scrollHeight)
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
        VStack(alignment: .leading, spacing: Self.spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrollHeight: CGFloat? {
        guard let maxHeight, bodyHeight > 0 else { return nil }
        let available = maxHeight - 2 * Self.padding - headerHeight - footerHeight - 2 * Self.spacing
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
            .background(.quaternary, in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Juicy tarzı daraltılabilir bölüm: simgeli başlık + chevron; durum `PanelConfig.detailCollapsed` içinde hatırlanır.
struct PanelDetailSection<Content: View, Accessory: View>: View {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    @Binding var config: PanelConfig
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let collapsed = config.isDetailCollapsed(id)
        PanelCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.panel(reduceMotion: reduceMotion)) { config.toggleDetailCollapsed(id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                            .frame(width: 22, height: 22)
                            .background(tint.opacity(0.16), in: .circle)
                        Text(title).font(.callout.weight(.semibold))
                        Spacer(minLength: 6)
                        accessory.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(collapsed ? 180 : 0))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(collapsed ? "Daraltıldı" : "Açık")
                .accessibilityHint(collapsed ? "Bölümü aç" : "Bölümü daralt")
                if !collapsed {
                    Divider().opacity(0.5)
                    VStack(alignment: .leading, spacing: 10) { content }
                        .padding(12)
                        .transition(.opacity)
                }
            }
        }
    }
}
